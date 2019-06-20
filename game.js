
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
Module['FS_createPath']('/OC/lib', 'core', true, true);
Module['FS_createPath']('/OC/lib/core', 'devfs', true, true);
Module['FS_createPath']('/OC/lib/core/devfs', 'adapters', true, true);
Module['FS_createPath']('/OC/lib', 'tools', true, true);
Module['FS_createPath']('/OC', 'synaptic', true, true);
Module['FS_createPath']('/', 'Optimized Synaptic', true, true);
Module['FS_createPath']('/', 'test', true, true);

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
 loadPackage({"files": [{"audio": 0, "start": 0, "crunched": 0, "end": 11295, "filename": "/colorFactory.lua"}, {"audio": 0, "start": 11295, "crunched": 0, "end": 586963, "filename": "/FixedsysExcelsior.ttf"}, {"audio": 0, "start": 586963, "crunched": 0, "end": 592108, "filename": "/flux.lua"}, {"audio": 0, "start": 592108, "crunched": 0, "end": 600742, "filename": "/luaneural.lua"}, {"audio": 0, "start": 600742, "crunched": 0, "end": 614198, "filename": "/main.lua"}, {"audio": 0, "start": 614198, "crunched": 0, "end": 630705, "filename": "/mo.lua"}, {"audio": 0, "start": 630705, "crunched": 0, "end": 630937, "filename": "/options.lua"}, {"audio": 0, "start": 630937, "crunched": 0, "end": 634874, "filename": "/outsideFix.lua"}, {"audio": 0, "start": 634874, "crunched": 0, "end": 638479, "filename": "/ser.lua"}, {"audio": 0, "start": 638479, "crunched": 0, "end": 640813, "filename": "/serialize.lua"}, {"audio": 0, "start": 640813, "crunched": 0, "end": 695351, "filename": "/svglover.lua"}, {"audio": 0, "start": 695351, "crunched": 0, "end": 704501, "filename": "/synapticRenderer.lua"}, {"audio": 0, "start": 704501, "crunched": 0, "end": 710479, "filename": "/vector.lua"}, {"audio": 0, "start": 710479, "crunched": 0, "end": 713371, "filename": "/gooi/bar.lua"}, {"audio": 0, "start": 713371, "crunched": 0, "end": 717598, "filename": "/gooi/button.lua"}, {"audio": 0, "start": 717598, "crunched": 0, "end": 719181, "filename": "/gooi/checkbox.lua"}, {"audio": 0, "start": 719181, "crunched": 0, "end": 733536, "filename": "/gooi/component.lua"}, {"audio": 0, "start": 733536, "crunched": 0, "end": 757799, "filename": "/gooi/gooi.lua"}, {"audio": 0, "start": 757799, "crunched": 0, "end": 759834, "filename": "/gooi/init.lua"}, {"audio": 0, "start": 759834, "crunched": 0, "end": 766514, "filename": "/gooi/joy.lua"}, {"audio": 0, "start": 766514, "crunched": 0, "end": 769882, "filename": "/gooi/knob.lua"}, {"audio": 0, "start": 769882, "crunched": 0, "end": 774046, "filename": "/gooi/label.lua"}, {"audio": 0, "start": 774046, "crunched": 0, "end": 777975, "filename": "/gooi/layout.lua"}, {"audio": 0, "start": 777975, "crunched": 0, "end": 785443, "filename": "/gooi/panel.lua"}, {"audio": 0, "start": 785443, "crunched": 0, "end": 787399, "filename": "/gooi/radio.lua"}, {"audio": 0, "start": 787399, "crunched": 0, "end": 792198, "filename": "/gooi/slider.lua"}, {"audio": 0, "start": 792198, "crunched": 0, "end": 796565, "filename": "/gooi/spinner.lua"}, {"audio": 0, "start": 796565, "crunched": 0, "end": 803824, "filename": "/gooi/text.lua"}, {"audio": 0, "start": 803824, "crunched": 0, "end": 814560, "filename": "/gooi/utf8.lua"}, {"audio": 0, "start": 814560, "crunched": 0, "end": 816731, "filename": "/images/bedrock.png"}, {"audio": 0, "start": 816731, "crunched": 0, "end": 818348, "filename": "/images/dirt.png"}, {"audio": 0, "start": 818348, "crunched": 0, "end": 820352, "filename": "/images/grass.png"}, {"audio": 0, "start": 820352, "crunched": 0, "end": 822463, "filename": "/images/player_head1.png"}, {"audio": 0, "start": 822463, "crunched": 0, "end": 824519, "filename": "/images/stone.png"}, {"audio": 0, "start": 824519, "crunched": 0, "end": 826547, "filename": "/moonshine/boxblur.lua"}, {"audio": 0, "start": 826547, "crunched": 0, "end": 828129, "filename": "/moonshine/chromasep.lua"}, {"audio": 0, "start": 828129, "crunched": 0, "end": 829260, "filename": "/moonshine/colorgradesimple.lua"}, {"audio": 0, "start": 829260, "crunched": 0, "end": 831690, "filename": "/moonshine/crt.lua"}, {"audio": 0, "start": 831690, "crunched": 0, "end": 833290, "filename": "/moonshine/desaturate.lua"}, {"audio": 0, "start": 833290, "crunched": 0, "end": 837686, "filename": "/moonshine/dmg.lua"}, {"audio": 0, "start": 837686, "crunched": 0, "end": 843003, "filename": "/moonshine/fastgaussianblur.lua"}, {"audio": 0, "start": 843003, "crunched": 0, "end": 845008, "filename": "/moonshine/filmgrain.lua"}, {"audio": 0, "start": 845008, "crunched": 0, "end": 848067, "filename": "/moonshine/fog.lua"}, {"audio": 0, "start": 848067, "crunched": 0, "end": 849996, "filename": "/moonshine/gaussianblur.lua"}, {"audio": 0, "start": 849996, "crunched": 0, "end": 853429, "filename": "/moonshine/glow.lua"}, {"audio": 0, "start": 853429, "crunched": 0, "end": 856675, "filename": "/moonshine/godsray.lua"}, {"audio": 0, "start": 856675, "crunched": 0, "end": 861607, "filename": "/moonshine/init.lua"}, {"audio": 0, "start": 861607, "crunched": 0, "end": 863423, "filename": "/moonshine/pixelate.lua"}, {"audio": 0, "start": 863423, "crunched": 0, "end": 865410, "filename": "/moonshine/posterize.lua"}, {"audio": 0, "start": 865410, "crunched": 0, "end": 879740, "filename": "/moonshine/README.md"}, {"audio": 0, "start": 879740, "crunched": 0, "end": 882075, "filename": "/moonshine/scanlines.lua"}, {"audio": 0, "start": 882075, "crunched": 0, "end": 884289, "filename": "/moonshine/sketch.lua"}, {"audio": 0, "start": 884289, "crunched": 0, "end": 886176, "filename": "/moonshine/vignette.lua"}, {"audio": 0, "start": 886176, "crunched": 0, "end": 886974, "filename": "/OC/init.lua"}, {"audio": 0, "start": 886974, "crunched": 0, "end": 903040, "filename": "/OC/neuralRobotTest.lua"}, {"audio": 0, "start": 903040, "crunched": 0, "end": 918482, "filename": "/OC/neuralRobotTest.moon"}, {"audio": 0, "start": 918482, "crunched": 0, "end": 922619, "filename": "/OC/robotNavigation.lua"}, {"audio": 0, "start": 922619, "crunched": 0, "end": 923952, "filename": "/OC/test.lua"}, {"audio": 0, "start": 923952, "crunched": 0, "end": 929559, "filename": "/OC/utils.lua"}, {"audio": 0, "start": 929559, "crunched": 0, "end": 931647, "filename": "/OC/lib/bit32.lua"}, {"audio": 0, "start": 931647, "crunched": 0, "end": 936152, "filename": "/OC/lib/buffer.lua"}, {"audio": 0, "start": 936152, "crunched": 0, "end": 936614, "filename": "/OC/lib/colors.lua"}, {"audio": 0, "start": 936614, "crunched": 0, "end": 945442, "filename": "/OC/lib/devfs.lua"}, {"audio": 0, "start": 945442, "crunched": 0, "end": 950089, "filename": "/OC/lib/event.lua"}, {"audio": 0, "start": 950089, "crunched": 0, "end": 958320, "filename": "/OC/lib/filesystem.lua"}, {"audio": 0, "start": 958320, "crunched": 0, "end": 961388, "filename": "/OC/lib/internet.lua"}, {"audio": 0, "start": 961388, "crunched": 0, "end": 964299, "filename": "/OC/lib/io.lua"}, {"audio": 0, "start": 964299, "crunched": 0, "end": 966320, "filename": "/OC/lib/keyboard.lua"}, {"audio": 0, "start": 966320, "crunched": 0, "end": 969754, "filename": "/OC/lib/note.lua"}, {"audio": 0, "start": 969754, "crunched": 0, "end": 972034, "filename": "/OC/lib/package.lua"}, {"audio": 0, "start": 972034, "crunched": 0, "end": 979444, "filename": "/OC/lib/pipe.lua"}, {"audio": 0, "start": 979444, "crunched": 0, "end": 984526, "filename": "/OC/lib/process.lua"}, {"audio": 0, "start": 984526, "crunched": 0, "end": 984673, "filename": "/OC/lib/rc.lua"}, {"audio": 0, "start": 984673, "crunched": 0, "end": 989218, "filename": "/OC/lib/serialization.lua"}, {"audio": 0, "start": 989218, "crunched": 0, "end": 995242, "filename": "/OC/lib/sh.lua"}, {"audio": 0, "start": 995242, "crunched": 0, "end": 999285, "filename": "/OC/lib/shell.lua"}, {"audio": 0, "start": 999285, "crunched": 0, "end": 1000301, "filename": "/OC/lib/sides.lua"}, {"audio": 0, "start": 1000301, "crunched": 0, "end": 1004824, "filename": "/OC/lib/term.lua"}, {"audio": 0, "start": 1004824, "crunched": 0, "end": 1007973, "filename": "/OC/lib/text.lua"}, {"audio": 0, "start": 1007973, "crunched": 0, "end": 1017099, "filename": "/OC/lib/thread.lua"}, {"audio": 0, "start": 1017099, "crunched": 0, "end": 1018931, "filename": "/OC/lib/transforms.lua"}, {"audio": 0, "start": 1018931, "crunched": 0, "end": 1026749, "filename": "/OC/lib/tty.lua"}, {"audio": 0, "start": 1026749, "crunched": 0, "end": 1027441, "filename": "/OC/lib/uuid.lua"}, {"audio": 0, "start": 1027441, "crunched": 0, "end": 1030778, "filename": "/OC/lib/vt100.lua"}, {"audio": 0, "start": 1030778, "crunched": 0, "end": 1034899, "filename": "/OC/lib/core/boot.lua"}, {"audio": 0, "start": 1034899, "crunched": 0, "end": 1042882, "filename": "/OC/lib/core/cursor.lua"}, {"audio": 0, "start": 1042882, "crunched": 0, "end": 1045504, "filename": "/OC/lib/core/device_labeling.lua"}, {"audio": 0, "start": 1045504, "crunched": 0, "end": 1050880, "filename": "/OC/lib/core/full_buffer.lua"}, {"audio": 0, "start": 1050880, "crunched": 0, "end": 1054684, "filename": "/OC/lib/core/full_cursor.lua"}, {"audio": 0, "start": 1054684, "crunched": 0, "end": 1056409, "filename": "/OC/lib/core/full_event.lua"}, {"audio": 0, "start": 1056409, "crunched": 0, "end": 1066537, "filename": "/OC/lib/core/full_filesystem.lua"}, {"audio": 0, "start": 1066537, "crunched": 0, "end": 1071418, "filename": "/OC/lib/core/full_keyboard.lua"}, {"audio": 0, "start": 1071418, "crunched": 0, "end": 1082526, "filename": "/OC/lib/core/full_ls.lua"}, {"audio": 0, "start": 1082526, "crunched": 0, "end": 1100844, "filename": "/OC/lib/core/full_sh.lua"}, {"audio": 0, "start": 1100844, "crunched": 0, "end": 1101450, "filename": "/OC/lib/core/full_shell.lua"}, {"audio": 0, "start": 1101450, "crunched": 0, "end": 1109619, "filename": "/OC/lib/core/full_text.lua"}, {"audio": 0, "start": 1109619, "crunched": 0, "end": 1112355, "filename": "/OC/lib/core/full_transforms.lua"}, {"audio": 0, "start": 1112355, "crunched": 0, "end": 1115247, "filename": "/OC/lib/core/full_vt.lua"}, {"audio": 0, "start": 1115247, "crunched": 0, "end": 1121451, "filename": "/OC/lib/core/install_basics.lua"}, {"audio": 0, "start": 1121451, "crunched": 0, "end": 1123433, "filename": "/OC/lib/core/install_utils.lua"}, {"audio": 0, "start": 1123433, "crunched": 0, "end": 1127208, "filename": "/OC/lib/core/lua_shell.lua"}, {"audio": 0, "start": 1127208, "crunched": 0, "end": 1131022, "filename": "/OC/lib/core/devfs/01_hw.lua"}, {"audio": 0, "start": 1131022, "crunched": 0, "end": 1132083, "filename": "/OC/lib/core/devfs/02_utils.lua"}, {"audio": 0, "start": 1132083, "crunched": 0, "end": 1132315, "filename": "/OC/lib/core/devfs/adapters/computer.lua"}, {"audio": 0, "start": 1132315, "crunched": 0, "end": 1132867, "filename": "/OC/lib/core/devfs/adapters/eeprom.lua"}, {"audio": 0, "start": 1132867, "crunched": 0, "end": 1133505, "filename": "/OC/lib/core/devfs/adapters/filesystem.lua"}, {"audio": 0, "start": 1133505, "crunched": 0, "end": 1134299, "filename": "/OC/lib/core/devfs/adapters/gpu.lua"}, {"audio": 0, "start": 1134299, "crunched": 0, "end": 1134427, "filename": "/OC/lib/core/devfs/adapters/internet.lua"}, {"audio": 0, "start": 1134427, "crunched": 0, "end": 1134714, "filename": "/OC/lib/core/devfs/adapters/modem.lua"}, {"audio": 0, "start": 1134714, "crunched": 0, "end": 1135316, "filename": "/OC/lib/core/devfs/adapters/screen.lua"}, {"audio": 0, "start": 1135316, "crunched": 0, "end": 1136184, "filename": "/OC/lib/tools/programLocations.lua"}, {"audio": 0, "start": 1136184, "crunched": 0, "end": 1143731, "filename": "/OC/lib/tools/transfer.lua"}, {"audio": 0, "start": 1143731, "crunched": 0, "end": 1144257, "filename": "/OC/synaptic/Connection.lua"}, {"audio": 0, "start": 1144257, "crunched": 0, "end": 1144345, "filename": "/OC/synaptic/init.lua"}, {"audio": 0, "start": 1144345, "crunched": 0, "end": 1149810, "filename": "/OC/synaptic/Layer.lua"}, {"audio": 0, "start": 1149810, "crunched": 0, "end": 1151783, "filename": "/OC/synaptic/LayerConnection.lua"}, {"audio": 0, "start": 1151783, "crunched": 0, "end": 1154877, "filename": "/OC/synaptic/LSTM.lua"}, {"audio": 0, "start": 1154877, "crunched": 0, "end": 1158059, "filename": "/OC/synaptic/Network.lua"}, {"audio": 0, "start": 1158059, "crunched": 0, "end": 1167932, "filename": "/OC/synaptic/Neuron.lua"}, {"audio": 0, "start": 1167932, "crunched": 0, "end": 1167955, "filename": "/OC/synaptic/options.lua"}, {"audio": 0, "start": 1167955, "crunched": 0, "end": 1169002, "filename": "/OC/synaptic/Perceptron.lua"}, {"audio": 0, "start": 1169002, "crunched": 0, "end": 1202649, "filename": "/Optimized Synaptic/LSTM_10_7_5"}, {"audio": 0, "start": 1202649, "crunched": 0, "end": 1388615, "filename": "/Optimized Synaptic/LSTM_10_7_5.lua"}, {"audio": 0, "start": 1388615, "crunched": 0, "end": 2989448, "filename": "/Optimized Synaptic/LSTM_13_15_15_5.lua"}, {"audio": 0, "start": 2989448, "crunched": 0, "end": 3152336, "filename": "/Optimized Synaptic/LSTM_8_20_5"}, {"audio": 0, "start": 3152336, "crunched": 0, "end": 3948292, "filename": "/Optimized Synaptic/LSTM_8_20_5.lua"}, {"audio": 0, "start": 3948292, "crunched": 0, "end": 3949621, "filename": "/test/main.lua"}, {"audio": 0, "start": 3949621, "crunched": 0, "end": 3953700, "filename": "/test/roundedRect.ply"}], "remote_package_size": 3953700, "package_uuid": "33de3cac-f79e-48db-8591-ed4c7ee45a2d"});

})();
