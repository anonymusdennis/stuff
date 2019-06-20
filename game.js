
var Module;

if (typeof Module === 'undefined') Module = eval('(function() { try { return Module || {} } catch(e) { return {} } })()');

if (!Module.expectedDataFileDownloads) {
  Module.expectedDataFileDownloads = 0;
  Module.finishedDataFileDownloads = 0;
}
Module.expectedDataFileDownloads++;
(function() {
 var loadPackage = function(metadata) {

    var PACKAGE_PATH;
    if (typeof window === 'object') {
      PACKAGE_PATH = window['encodeURIComponent'](window.location.pathname.toString().substring(0, window.location.pathname.toString().lastIndexOf('/')) + '/');
    } else if (typeof location !== 'undefined') {
      // worker
      PACKAGE_PATH = encodeURIComponent(location.pathname.toString().substring(0, location.pathname.toString().lastIndexOf('/')) + '/');
    } else {
      throw 'using preloaded data can only be done on a web page or in a web worker';
    }
    var PACKAGE_NAME = 'game.data';
    var REMOTE_PACKAGE_BASE = 'game.data';
    if (typeof Module['locateFilePackage'] === 'function' && !Module['locateFile']) {
      Module['locateFile'] = Module['locateFilePackage'];
      Module.printErr('warning: you defined Module.locateFilePackage, that has been renamed to Module.locateFile (using your locateFilePackage for now)');
    }
    var REMOTE_PACKAGE_NAME = typeof Module['locateFile'] === 'function' ?
                              Module['locateFile'](REMOTE_PACKAGE_BASE) :
                              ((Module['filePackagePrefixURL'] || '') + REMOTE_PACKAGE_BASE);
  
    var REMOTE_PACKAGE_SIZE = metadata.remote_package_size;
    var PACKAGE_UUID = metadata.package_uuid;
  
    function fetchRemotePackage(packageName, packageSize, callback, errback) {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', packageName, true);
      xhr.responseType = 'arraybuffer';
      xhr.onprogress = function(event) {
        var url = packageName;
        var size = packageSize;
        if (event.total) size = event.total;
        if (event.loaded) {
          if (!xhr.addedTotal) {
            xhr.addedTotal = true;
            if (!Module.dataFileDownloads) Module.dataFileDownloads = {};
            Module.dataFileDownloads[url] = {
              loaded: event.loaded,
              total: size
            };
          } else {
            Module.dataFileDownloads[url].loaded = event.loaded;
          }
          var total = 0;
          var loaded = 0;
          var num = 0;
          for (var download in Module.dataFileDownloads) {
          var data = Module.dataFileDownloads[download];
            total += data.total;
            loaded += data.loaded;
            num++;
          }
          total = Math.ceil(total * Module.expectedDataFileDownloads/num);
          if (Module['setStatus']) Module['setStatus']('Downloading data... (' + loaded + '/' + total + ')');
        } else if (!Module.dataFileDownloads) {
          if (Module['setStatus']) Module['setStatus']('Downloading data...');
        }
      };
      xhr.onload = function(event) {
        var packageData = xhr.response;
        callback(packageData);
      };
      xhr.send(null);
    };

    function handleError(error) {
      console.error('package error:', error);
    };
  
      var fetched = null, fetchedCallback = null;
      fetchRemotePackage(REMOTE_PACKAGE_NAME, REMOTE_PACKAGE_SIZE, function(data) {
        if (fetchedCallback) {
          fetchedCallback(data);
          fetchedCallback = null;
        } else {
          fetched = data;
        }
      }, handleError);
    
  function runWithFS() {

    function assert(check, msg) {
      if (!check) throw msg + new Error().stack;
    }
Module['FS_createPath']('/', 'gooi', true, true);
Module['FS_createPath']('/', 'images', true, true);
Module['FS_createPath']('/', 'moonshine', true, true);
Module['FS_createPath']('/', 'OC', true, true);
Module['FS_createPath']('/OC', 'lib', true, true);
Module['FS_createPath']('/OC', 'synaptic', true, true);

    function DataRequest(start, end, crunched, audio) {
      this.start = start;
      this.end = end;
      this.crunched = crunched;
      this.audio = audio;
    }
    DataRequest.prototype = {
      requests: {},
      open: function(mode, name) {
        this.name = name;
        this.requests[name] = this;
        Module['addRunDependency']('fp ' + this.name);
      },
      send: function() {},
      onload: function() {
        var byteArray = this.byteArray.subarray(this.start, this.end);

          this.finish(byteArray);

      },
      finish: function(byteArray) {
        var that = this;

        Module['FS_createDataFile'](this.name, null, byteArray, true, true, true); // canOwn this data in the filesystem, it is a slide into the heap that will never change
        Module['removeRunDependency']('fp ' + that.name);

        this.requests[this.name] = null;
      },
    };

        var files = metadata.files;
        for (i = 0; i < files.length; ++i) {
          new DataRequest(files[i].start, files[i].end, files[i].crunched, files[i].audio).open('GET', files[i].filename);
        }

  
    function processPackageData(arrayBuffer) {
      Module.finishedDataFileDownloads++;
      assert(arrayBuffer, 'Loading data file failed.');
      assert(arrayBuffer instanceof ArrayBuffer, 'bad input to processPackageData');
      var byteArray = new Uint8Array(arrayBuffer);
      var curr;
      
        // copy the entire loaded file into a spot in the heap. Files will refer to slices in that. They cannot be freed though
        // (we may be allocating before malloc is ready, during startup).
        if (Module['SPLIT_MEMORY']) Module.printErr('warning: you should run the file packager with --no-heap-copy when SPLIT_MEMORY is used, otherwise copying into the heap may fail due to the splitting');
        var ptr = Module['getMemory'](byteArray.length);
        Module['HEAPU8'].set(byteArray, ptr);
        DataRequest.prototype.byteArray = Module['HEAPU8'].subarray(ptr, ptr+byteArray.length);
  
          var files = metadata.files;
          for (i = 0; i < files.length; ++i) {
            DataRequest.prototype.requests[files[i].filename].onload();
          }
              Module['removeRunDependency']('datafile_game.data');

    };
    Module['addRunDependency']('datafile_game.data');
  
    if (!Module.preloadResults) Module.preloadResults = {};
  
      Module.preloadResults[PACKAGE_NAME] = {fromCache: false};
      if (fetched) {
        processPackageData(fetched);
        fetched = null;
      } else {
        fetchedCallback = processPackageData;
      }
    
  }
  if (Module['calledRun']) {
    runWithFS();
  } else {
    if (!Module['preRun']) Module['preRun'] = [];
    Module["preRun"].push(runWithFS); // FS is not initialized yet, wait for it
  }

 }
 loadPackage({"files": [{"audio": 0, "start": 0, "crunched": 0, "end": 66, "filename": "/.gitattributes"}, {"audio": 0, "start": 66, "crunched": 0, "end": 11361, "filename": "/colorFactory.lua"}, {"audio": 0, "start": 11361, "crunched": 0, "end": 587029, "filename": "/FixedsysExcelsior.ttf"}, {"audio": 0, "start": 587029, "crunched": 0, "end": 592174, "filename": "/flux.lua"}, {"audio": 0, "start": 592174, "crunched": 0, "end": 600808, "filename": "/luaneural.lua"}, {"audio": 0, "start": 600808, "crunched": 0, "end": 614284, "filename": "/main.lua"}, {"audio": 0, "start": 614284, "crunched": 0, "end": 630010, "filename": "/mo.lua"}, {"audio": 0, "start": 630010, "crunched": 0, "end": 630242, "filename": "/options.lua"}, {"audio": 0, "start": 630242, "crunched": 0, "end": 634157, "filename": "/outsideFix.lua"}, {"audio": 0, "start": 634157, "crunched": 0, "end": 634172, "filename": "/README.md"}, {"audio": 0, "start": 634172, "crunched": 0, "end": 637777, "filename": "/ser.lua"}, {"audio": 0, "start": 637777, "crunched": 0, "end": 640111, "filename": "/serialize.lua"}, {"audio": 0, "start": 640111, "crunched": 0, "end": 694649, "filename": "/svglover.lua"}, {"audio": 0, "start": 694649, "crunched": 0, "end": 703797, "filename": "/synapticRenderer.lua"}, {"audio": 0, "start": 703797, "crunched": 0, "end": 709775, "filename": "/vector.lua"}, {"audio": 0, "start": 709775, "crunched": 0, "end": 712667, "filename": "/gooi/bar.lua"}, {"audio": 0, "start": 712667, "crunched": 0, "end": 716894, "filename": "/gooi/button.lua"}, {"audio": 0, "start": 716894, "crunched": 0, "end": 718477, "filename": "/gooi/checkbox.lua"}, {"audio": 0, "start": 718477, "crunched": 0, "end": 732832, "filename": "/gooi/component.lua"}, {"audio": 0, "start": 732832, "crunched": 0, "end": 757095, "filename": "/gooi/gooi.lua"}, {"audio": 0, "start": 757095, "crunched": 0, "end": 759130, "filename": "/gooi/init.lua"}, {"audio": 0, "start": 759130, "crunched": 0, "end": 765810, "filename": "/gooi/joy.lua"}, {"audio": 0, "start": 765810, "crunched": 0, "end": 769178, "filename": "/gooi/knob.lua"}, {"audio": 0, "start": 769178, "crunched": 0, "end": 773342, "filename": "/gooi/label.lua"}, {"audio": 0, "start": 773342, "crunched": 0, "end": 777271, "filename": "/gooi/layout.lua"}, {"audio": 0, "start": 777271, "crunched": 0, "end": 784739, "filename": "/gooi/panel.lua"}, {"audio": 0, "start": 784739, "crunched": 0, "end": 786695, "filename": "/gooi/radio.lua"}, {"audio": 0, "start": 786695, "crunched": 0, "end": 791494, "filename": "/gooi/slider.lua"}, {"audio": 0, "start": 791494, "crunched": 0, "end": 795861, "filename": "/gooi/spinner.lua"}, {"audio": 0, "start": 795861, "crunched": 0, "end": 803120, "filename": "/gooi/text.lua"}, {"audio": 0, "start": 803120, "crunched": 0, "end": 813856, "filename": "/gooi/utf8.lua"}, {"audio": 0, "start": 813856, "crunched": 0, "end": 816027, "filename": "/images/bedrock.png"}, {"audio": 0, "start": 816027, "crunched": 0, "end": 817644, "filename": "/images/dirt.png"}, {"audio": 0, "start": 817644, "crunched": 0, "end": 819648, "filename": "/images/grass.png"}, {"audio": 0, "start": 819648, "crunched": 0, "end": 821759, "filename": "/images/player_head1.png"}, {"audio": 0, "start": 821759, "crunched": 0, "end": 823815, "filename": "/images/stone.png"}, {"audio": 0, "start": 823815, "crunched": 0, "end": 825843, "filename": "/moonshine/boxblur.lua"}, {"audio": 0, "start": 825843, "crunched": 0, "end": 827425, "filename": "/moonshine/chromasep.lua"}, {"audio": 0, "start": 827425, "crunched": 0, "end": 828556, "filename": "/moonshine/colorgradesimple.lua"}, {"audio": 0, "start": 828556, "crunched": 0, "end": 830986, "filename": "/moonshine/crt.lua"}, {"audio": 0, "start": 830986, "crunched": 0, "end": 832586, "filename": "/moonshine/desaturate.lua"}, {"audio": 0, "start": 832586, "crunched": 0, "end": 836982, "filename": "/moonshine/dmg.lua"}, {"audio": 0, "start": 836982, "crunched": 0, "end": 842299, "filename": "/moonshine/fastgaussianblur.lua"}, {"audio": 0, "start": 842299, "crunched": 0, "end": 844304, "filename": "/moonshine/filmgrain.lua"}, {"audio": 0, "start": 844304, "crunched": 0, "end": 847363, "filename": "/moonshine/fog.lua"}, {"audio": 0, "start": 847363, "crunched": 0, "end": 849292, "filename": "/moonshine/gaussianblur.lua"}, {"audio": 0, "start": 849292, "crunched": 0, "end": 852725, "filename": "/moonshine/glow.lua"}, {"audio": 0, "start": 852725, "crunched": 0, "end": 855971, "filename": "/moonshine/godsray.lua"}, {"audio": 0, "start": 855971, "crunched": 0, "end": 860903, "filename": "/moonshine/init.lua"}, {"audio": 0, "start": 860903, "crunched": 0, "end": 862719, "filename": "/moonshine/pixelate.lua"}, {"audio": 0, "start": 862719, "crunched": 0, "end": 864706, "filename": "/moonshine/posterize.lua"}, {"audio": 0, "start": 864706, "crunched": 0, "end": 879036, "filename": "/moonshine/README.md"}, {"audio": 0, "start": 879036, "crunched": 0, "end": 881371, "filename": "/moonshine/scanlines.lua"}, {"audio": 0, "start": 881371, "crunched": 0, "end": 883585, "filename": "/moonshine/sketch.lua"}, {"audio": 0, "start": 883585, "crunched": 0, "end": 885472, "filename": "/moonshine/vignette.lua"}, {"audio": 0, "start": 885472, "crunched": 0, "end": 886270, "filename": "/OC/init.lua"}, {"audio": 0, "start": 886270, "crunched": 0, "end": 902318, "filename": "/OC/neuralRobotTest.lua"}, {"audio": 0, "start": 902318, "crunched": 0, "end": 917721, "filename": "/OC/neuralRobotTest.moon"}, {"audio": 0, "start": 917721, "crunched": 0, "end": 921857, "filename": "/OC/robotNavigation.lua"}, {"audio": 0, "start": 921857, "crunched": 0, "end": 923190, "filename": "/OC/test.lua"}, {"audio": 0, "start": 923190, "crunched": 0, "end": 929174, "filename": "/OC/utils.lua"}, {"audio": 0, "start": 929174, "crunched": 0, "end": 930190, "filename": "/OC/lib/sides.lua"}, {"audio": 0, "start": 930190, "crunched": 0, "end": 930716, "filename": "/OC/synaptic/Connection.lua"}, {"audio": 0, "start": 930716, "crunched": 0, "end": 930804, "filename": "/OC/synaptic/init.lua"}, {"audio": 0, "start": 930804, "crunched": 0, "end": 936269, "filename": "/OC/synaptic/Layer.lua"}, {"audio": 0, "start": 936269, "crunched": 0, "end": 938242, "filename": "/OC/synaptic/LayerConnection.lua"}, {"audio": 0, "start": 938242, "crunched": 0, "end": 941336, "filename": "/OC/synaptic/LSTM.lua"}, {"audio": 0, "start": 941336, "crunched": 0, "end": 944518, "filename": "/OC/synaptic/Network.lua"}, {"audio": 0, "start": 944518, "crunched": 0, "end": 954391, "filename": "/OC/synaptic/Neuron.lua"}, {"audio": 0, "start": 954391, "crunched": 0, "end": 954414, "filename": "/OC/synaptic/options.lua"}, {"audio": 0, "start": 954414, "crunched": 0, "end": 955461, "filename": "/OC/synaptic/Perceptron.lua"}], "remote_package_size": 955461, "package_uuid": "31646d23-0268-4dff-9bb4-c1f933ec9451"});

})();
