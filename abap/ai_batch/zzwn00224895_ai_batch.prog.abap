REPORT zzwn00224895_ai_batch.

"----------------------------------------------------------------------
" KI-Massenverarbeitung
"
" Verarbeitungsmodi:
"  1. Entwicklungsobjekte: Selektion über TADIR (bisheriges Verhalten).
"  2. Promptliste: eine Zeile = ein Prompt. Quellen sind die Promptzeilen
"     (Editor oder PC-Import aus TXT/CSV/XLSX), eine Serverdatei
"     (TXT/XLSX) oder im Template-Modus ein Template mit Platzhaltern
"     der Form %NAME%. Jeder Platzhalter wird zu einem Wertefeld; alle
"     Wertekombinationen werden zu Prompts expandiert.
"
" Alle Eingaben sind reguläre Selektionsbildfelder und damit
" variantenfähig. Die Beschriftung der Wertefelder wird bei jedem
" Bildaufbau aus dem Template abgeleitet.
"----------------------------------------------------------------------

TABLES:
  sscrfields,
  tadir.

TYPES:
  ty_prompt_line TYPE c LENGTH 255,
  ty_api_name    TYPE c LENGTH 40,
  ty_tpl_value   TYPE c LENGTH 132.

TYPES:
  BEGIN OF ty_object,
    kind         TYPE c LENGTH 1,
    object       TYPE tadir-object,
    obj_name     TYPE tadir-obj_name,
    devclass     TYPE tadir-devclass,
    author       TYPE tadir-author,

    " Zusätzliche Metadaten für Funktionsbausteine
    funcname     TYPE tfdir-funcname,
    func_group   TYPE enlfdir-area,
    func_pool    TYPE tfdir-pname,
    func_include TYPE tfdir-include,
    fmode        TYPE tfdir-fmode,
    utask        TYPE tfdir-utask,
    generated    TYPE enlfdir-generated,

    " Promptlisten-Modus
    prompt_no    TYPE i,
    prompt_key   TYPE c LENGTH 40,
    prompt_text  TYPE string,
    tpl_values   TYPE string,
  END OF ty_object,
  tt_object TYPE STANDARD TABLE OF ty_object WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_result,
    idx         TYPE i,
    total       TYPE i,
    kind        TYPE c LENGTH 1,
    object      TYPE tadir-object,
    obj_name    TYPE tadir-obj_name,
    devclass    TYPE tadir-devclass,
    author      TYPE tadir-author,
    prompt_no   TYPE i,
    prompt_key  TYPE c LENGTH 40,
    prompt_text TYPE string,
    tpl_values  TYPE string,
    label       TYPE string,
    session_id  TYPE char32,
    status      TYPE c LENGTH 12,
    attempts    TYPE i,
    steps       TYPE i,
    duration_s  TYPE i,
    elapsed_s   TYPE i,
    eta_s       TYPE i,
    http_status TYPE i,
    error_text  TYPE string,
    answer      TYPE string,
    output_row  TYPE string,
  END OF ty_result,
  tt_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_expansion,
    text       TYPE string,
    value_text TYPE string,
  END OF ty_expansion,
  tt_expansion TYPE STANDARD TABLE OF ty_expansion WITH EMPTY KEY.

CONSTANTS:
  gc_ok       TYPE c LENGTH 12 VALUE 'OK',
  gc_error    TYPE c LENGTH 12 VALUE 'ERROR',
  gc_format   TYPE c LENGTH 12 VALUE 'FORMAT',
  gc_skipped  TYPE c LENGTH 12 VALUE 'SKIPPED',
  gc_maxsteps TYPE c LENGTH 12 VALUE 'MAXSTEPS',

  gc_kind_object TYPE c LENGTH 1 VALUE 'O',
  gc_kind_prompt TYPE c LENGTH 1 VALUE 'P',
  gc_item_prompt TYPE c LENGTH 6 VALUE 'PROMPT',

  gc_max_slots          TYPE i VALUE 10,
  gc_max_prompts        TYPE i VALUE 100000,
  gc_prompt_line_length TYPE i VALUE 255,
  gc_placeholder_regex  TYPE string VALUE '%([A-Za-z0-9_]+)%',

  gc_cmd_sysp TYPE sy-ucomm VALUE 'SYSP',
  gc_cmd_usrp TYPE sy-ucomm VALUE 'USRP',
  gc_cmd_down TYPE sy-ucomm VALUE 'DOWN',
  gc_cmd_prmp TYPE sy-ucomm VALUE 'PRMP',
  gc_cmd_prmi TYPE sy-ucomm VALUE 'PRMI',
  gc_cmd_tplp TYPE sy-ucomm VALUE 'TPLP'.

DATA:
  gv_prompt_line TYPE ty_prompt_line,
  gv_api_name    TYPE ty_api_name,
  gv_tpl_value   TYPE ty_tpl_value,
  gv_result_file TYPE string,
  gv_log_file    TYPE string,
  gt_results     TYPE tt_result.

"----------------------------------------------------------------------
" Selektionsbild
"----------------------------------------------------------------------
SELECTION-SCREEN BEGIN OF BLOCK b00 WITH FRAME TITLE gv_t00.
  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS p_mobj RADIOBUTTON GROUP mod DEFAULT 'X' USER-COMMAND mode.
    SELECTION-SCREEN COMMENT 3(60) gv_c01 FOR FIELD p_mobj.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS p_mprm RADIOBUTTON GROUP mod.
    SELECTION-SCREEN COMMENT 3(60) gv_c02 FOR FIELD p_mprm.
  SELECTION-SCREEN END OF LINE.

  PARAMETERS:
    p_maxobj TYPE i DEFAULT 0,
    p_resume AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b00.

" Nur im Modus "Entwicklungsobjekte" eingabebereit (MODIF ID OBJ).
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE gv_t01.
  SELECT-OPTIONS:
    s_objtyp FOR tadir-object NO INTERVALS DEFAULT 'PROG' MODIF ID obj,
    s_objnam FOR tadir-obj_name MODIF ID obj,
    s_devc   FOR tadir-devclass MODIF ID obj,
    s_author FOR tadir-author MODIF ID obj.

  PARAMETERS p_infile TYPE c LENGTH 255 LOWER CASE MODIF ID obj.
SELECTION-SCREEN END OF BLOCK b01.

" Nur im Modus "Promptliste" eingabebereit.
"   PRM = Promptliste (ohne Template-Modus)
"   PRA = Schalter Template-Modus
"   TPL = Template-Eingaben (Template-Modus)
"   V01..V10 = Wertefelder je Platzhalter (standardmäßig unsichtbar)
SELECTION-SCREEN BEGIN OF BLOCK b07 WITH FRAME TITLE gv_t07.
  SELECTION-SCREEN PUSHBUTTON /1(40) gv_b04 USER-COMMAND prmp MODIF ID prm.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_c04 FOR FIELD s_prm MODIF ID prm.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_prm FOR gv_prompt_line NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID prm.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_c05 FOR FIELD p_prmfil MODIF ID prm.
    SELECTION-SCREEN POSITION pos_low.
    PARAMETERS p_prmfil TYPE c LENGTH 255 LOWER CASE
      VISIBLE LENGTH 45 MODIF ID prm.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN PUSHBUTTON /1(40) gv_b05 USER-COMMAND prmi MODIF ID prm.

  SELECTION-SCREEN SKIP.

  SELECTION-SCREEN BEGIN OF LINE.
    PARAMETERS p_tplmod AS CHECKBOX USER-COMMAND mode MODIF ID pra.
    SELECTION-SCREEN COMMENT 3(60) gv_c03 FOR FIELD p_tplmod MODIF ID pra.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN PUSHBUTTON /1(40) gv_b06 USER-COMMAND tplp MODIF ID tpl.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_c06 FOR FIELD s_tpl MODIF ID tpl.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tpl FOR gv_prompt_line NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID tpl.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_c07 FOR FIELD p_tplfil MODIF ID tpl.
    SELECTION-SCREEN POSITION pos_low.
    PARAMETERS p_tplfil TYPE c LENGTH 255 LOWER CASE
      VISIBLE LENGTH 45 MODIF ID tpl.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN SKIP.

  " Wertefelder: Beschriftung und Sichtbarkeit werden in
  " AT SELECTION-SCREEN OUTPUT aus den Platzhaltern des Templates gesetzt.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l01 FOR FIELD s_tv01 MODIF ID v01.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv01 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v01.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l02 FOR FIELD s_tv02 MODIF ID v02.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv02 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v02.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l03 FOR FIELD s_tv03 MODIF ID v03.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv03 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v03.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l04 FOR FIELD s_tv04 MODIF ID v04.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv04 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v04.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l05 FOR FIELD s_tv05 MODIF ID v05.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv05 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v05.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l06 FOR FIELD s_tv06 MODIF ID v06.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv06 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v06.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l07 FOR FIELD s_tv07 MODIF ID v07.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv07 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v07.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l08 FOR FIELD s_tv08 MODIF ID v08.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv08 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v08.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l09 FOR FIELD s_tv09 MODIF ID v09.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv09 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v09.
  SELECTION-SCREEN END OF LINE.

  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(31) gv_l10 FOR FIELD s_tv10 MODIF ID v10.
    SELECTION-SCREEN POSITION pos_low.
    SELECT-OPTIONS s_tv10 FOR gv_tpl_value NO INTERVALS LOWER CASE
      VISIBLE LENGTH 45 MODIF ID v10.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b07.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE gv_t02.
  PARAMETERS:
    p_model  TYPE c LENGTH 100 LOWER CASE
      DEFAULT 'gpt-5.6-sol' OBLIGATORY,
    p_key    TYPE c LENGTH 255 LOWER CASE OBLIGATORY,
    p_reason TYPE c LENGTH 10 LOWER CASE,
    p_region TYPE c LENGTH 4 LOWER CASE DEFAULT 'eu'.

  SELECT-OPTIONS s_tools FOR gv_api_name NO INTERVALS.
SELECTION-SCREEN END OF BLOCK b02.

SELECTION-SCREEN BEGIN OF BLOCK b03 WITH FRAME TITLE gv_t03.
  SELECTION-SCREEN PUSHBUTTON /1(30) gv_b01 USER-COMMAND sysp.
  SELECT-OPTIONS s_sysp FOR gv_prompt_line NO INTERVALS.
  PARAMETERS p_sysfil TYPE c LENGTH 255 LOWER CASE.

  SELECTION-SCREEN SKIP.
  " Der Benutzerprompt je Objekt wird nur im Modus "Entwicklungsobjekte"
  " verwendet; im Promptlisten-Modus ist die Promptzeile der Benutzertext.
  SELECTION-SCREEN PUSHBUTTON /1(30) gv_b02 USER-COMMAND usrp MODIF ID obj.
  SELECT-OPTIONS s_usrp FOR gv_prompt_line NO INTERVALS MODIF ID obj.
  PARAMETERS p_usrfil TYPE c LENGTH 255 LOWER CASE MODIF ID obj.

  SELECTION-SCREEN SKIP.
  PARAMETERS p_usrone TYPE c LENGTH 255 LOWER CASE
    DEFAULT 'Analysiere genau &TYPE&:&NAME& aus Paket &DEVC&.'
    MODIF ID obj.
SELECTION-SCREEN END OF BLOCK b03.

SELECTION-SCREEN BEGIN OF BLOCK b04 WITH FRAME TITLE gv_t04.
  PARAMETERS:
    p_header TYPE c LENGTH 255 LOWER CASE OBLIGATORY
      DEFAULT 'OBJECT_TYPE\tOBJECT_NAME\tPACKAGE\tRESULT\tCONFIDENCE\tREASON',
    p_cols   TYPE i DEFAULT 6,
    p_strict AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b04.

SELECTION-SCREEN BEGIN OF BLOCK b05 WITH FRAME TITLE gv_t05.
  PARAMETERS:
    p_maxstp TYPE i DEFAULT 25,
    p_retry  TYPE i DEFAULT 0,
    p_wait   TYPE i DEFAULT 30,
    p_waitmx TYPE i DEFAULT 900,
    p_pause  TYPE i DEFAULT 0,
    p_logfrq TYPE i DEFAULT 1.
SELECTION-SCREEN END OF BLOCK b05.

SELECTION-SCREEN BEGIN OF BLOCK b06 WITH FRAME TITLE gv_t06.
  PARAMETERS:
    p_outdir TYPE c LENGTH 255 LOWER CASE
      DEFAULT '/usr/sap/trans/AI',
    p_file   TYPE c LENGTH 255 LOWER CASE,
    p_down   AS CHECKBOX DEFAULT 'X'.

  SELECTION-SCREEN PUSHBUTTON /1(35) gv_b03 USER-COMMAND down.
SELECTION-SCREEN END OF BLOCK b06.

"----------------------------------------------------------------------
" Klassendefinitionen
"----------------------------------------------------------------------
CLASS lcl_text DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      range_lows
        IMPORTING it_range         TYPE STANDARD TABLE
                  iv_skip_excluded TYPE abap_bool DEFAULT abap_false
        RETURNING VALUE(rt_lines)  TYPE string_table,

      join_range
        IMPORTING it_range       TYPE STANDARD TABLE
        RETURNING VALUE(rv_text) TYPE string,

      read_server_lines
        IMPORTING iv_file         TYPE string
                  iv_silent       TYPE abap_bool DEFAULT abap_false
        RETURNING VALUE(rt_lines) TYPE string_table,

      read_server_text
        IMPORTING iv_file        TYPE string
                  iv_silent      TYPE abap_bool DEFAULT abap_false
        RETURNING VALUE(rv_text) TYPE string,

      build_prompt
        IMPORTING it_range       TYPE STANDARD TABLE
                  iv_file        TYPE string
                  iv_default     TYPE string
                  iv_silent      TYPE abap_bool DEFAULT abap_false
        RETURNING VALUE(rv_text) TYPE string,

      replace_all
        IMPORTING iv_old  TYPE string
                  iv_new  TYPE string
        CHANGING  cv_text TYPE string,

      strip_cr
        IMPORTING iv_text        TYPE string
        RETURNING VALUE(rv_text) TYPE string,

      clean_cell
        IMPORTING iv_text        TYPE string
        RETURNING VALUE(rv_text) TYPE string,

      shorten
        IMPORTING iv_text        TYPE string
                  iv_length      TYPE i
        RETURNING VALUE(rv_text) TYPE string,

      normalize_answer
        IMPORTING iv_answer     TYPE string
        RETURNING VALUE(rv_row) TYPE string,

      count_columns
        IMPORTING iv_row         TYPE string
        RETURNING VALUE(rv_cols) TYPE i,

      duration_text
        IMPORTING iv_seconds     TYPE i
        RETURNING VALUE(rv_text) TYPE string,

      item_key
        IMPORTING iv_kind       TYPE ty_object-kind
                  iv_object     TYPE tadir-object
                  iv_obj_name   TYPE tadir-obj_name
        RETURNING VALUE(rv_key) TYPE string,

      item_label
        IMPORTING is_object      TYPE ty_object
        RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS lcl_prompt_file DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      read_server_lines
        IMPORTING iv_file         TYPE string
        RETURNING VALUE(rt_lines) TYPE string_table,

      read_frontend_lines
        RETURNING VALUE(rt_lines) TYPE string_table,

      is_xlsx
        IMPORTING iv_name       TYPE string
        RETURNING VALUE(rv_yes) TYPE abap_bool.

  PRIVATE SECTION.
    CLASS-METHODS:
      lines_from_xstring
        IMPORTING iv_name         TYPE string
                  iv_data         TYPE xstring
        RETURNING VALUE(rt_lines) TYPE string_table,

      xlsx_to_lines
        IMPORTING iv_name         TYPE string
                  iv_data         TYPE xstring
        RETURNING VALUE(rt_lines) TYPE string_table,

      text_to_lines
        IMPORTING iv_data         TYPE xstring
        RETURNING VALUE(rt_lines) TYPE string_table,

      decode
        IMPORTING iv_data        TYPE xstring
                  iv_codepage    TYPE abap_encoding
                  iv_strict      TYPE abap_bool
        RETURNING VALUE(rv_text) TYPE string
        RAISING   cx_sy_conversion_codepage
                  cx_sy_codepage_converter_init
                  cx_parameter_invalid,

      starts_with
        IMPORTING iv_data       TYPE xstring
                  iv_prefix     TYPE xsequence
        RETURNING VALUE(rv_yes) TYPE abap_bool,

      read_server_binary
        IMPORTING iv_file        TYPE string
        RETURNING VALUE(rv_data) TYPE xstring.
ENDCLASS.

CLASS lcl_template DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      read_template
        IMPORTING iv_silent      TYPE abap_bool DEFAULT abap_false
        RETURNING VALUE(rv_text) TYPE string,

      find_placeholders
        IMPORTING iv_text         TYPE string
        RETURNING VALUE(rt_names) TYPE string_table,

      slot_values
        IMPORTING iv_slot          TYPE i
        RETURNING VALUE(rt_values) TYPE string_table,

      expand
        IMPORTING iv_template       TYPE string
                  it_names          TYPE string_table
        RETURNING VALUE(rt_prompts) TYPE tt_expansion.
ENDCLASS.

CLASS lcl_object_resolver DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS get_objects
      RETURNING VALUE(rt_objects) TYPE tt_object.

    METHODS add_functions
      CHANGING ct_objects TYPE tt_object.

  PRIVATE SECTION.
    METHODS:
      add_from_tadir
        CHANGING ct_objects TYPE tt_object,

      add_from_file
        CHANGING ct_objects TYPE tt_object,

      enrich
        CHANGING cs_object TYPE ty_object,

      append_unique
        IMPORTING is_object  TYPE ty_object
        CHANGING  ct_objects TYPE tt_object.
ENDCLASS.

CLASS lcl_prompt_resolver DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS get_items
      RETURNING VALUE(rt_items) TYPE tt_object.

  PRIVATE SECTION.
    DATA:
      mt_seen    TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,
      mv_counter TYPE i.

    METHODS:
      add_from_list
        CHANGING ct_items TYPE tt_object,

      add_from_template
        CHANGING ct_items TYPE tt_object,

      append_prompt
        IMPORTING iv_text   TYPE string
                  iv_values TYPE string
        CHANGING  ct_items  TYPE tt_object,

      prompt_key
        IMPORTING iv_text       TYPE string
        RETURNING VALUE(rv_key) TYPE ty_object-prompt_key.
ENDCLASS.

CLASS lcl_screen DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      adjust,

      edit_range
        IMPORTING iv_title TYPE string
        CHANGING  ct_range TYPE STANDARD TABLE,

      import_prompt_list.

  PRIVATE SECTION.
    CLASS-METHODS set_slot_label
      IMPORTING iv_slot TYPE i
                iv_text TYPE string.
ENDCLASS.

CLASS lcl_tsv_writer DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS:
      constructor
        IMPORTING iv_result_file TYPE string
                  iv_log_file    TYPE string,

      initialize
        IMPORTING iv_header TYPE string
                  iv_resume TYPE abap_bool,

      write_result
        IMPORTING is_result TYPE ty_result,

      write_log
        IMPORTING iv_text TYPE string,

      already_done
        IMPORTING is_object      TYPE ty_object
        RETURNING VALUE(rv_done) TYPE abap_bool,

      download
        IMPORTING iv_server_file TYPE string.

  PRIVATE SECTION.
    DATA:
      mv_result_file TYPE string,
      mv_log_file    TYPE string,
      mt_done        TYPE HASHED TABLE OF string
                     WITH UNIQUE KEY table_line.

    METHODS:
      append_line
        IMPORTING iv_file TYPE string
                  iv_line TYPE string,

      load_done.
ENDCLASS.

CLASS lcl_progress DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS:
      constructor
        IMPORTING iv_total TYPE i,

      start,

      object_started
        IMPORTING iv_idx    TYPE i
                  is_object TYPE ty_object,

      object_finished
        IMPORTING is_result TYPE ty_result,

      info
        IMPORTING iv_text TYPE string,

      get_elapsed
        RETURNING VALUE(rv_seconds) TYPE i,

      get_eta
        IMPORTING iv_finished       TYPE i
        RETURNING VALUE(rv_seconds) TYPE i.

  PRIVATE SECTION.
    DATA:
      mv_total    TYPE i,
      mv_start_ts TYPE timestampl.
ENDCLASS.

CLASS lcl_batch_runner DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    DATA:
      mo_repo     TYPE REF TO zzwn00224895_ai_repo,
      mo_registry TYPE REF TO zzwn00224895_ai_registry,
      mo_client   TYPE REF TO zzwn00224895_ai_client,
      mo_orch     TYPE REF TO zzwn00224895_ai_orchestr,
      mo_writer   TYPE REF TO lcl_tsv_writer,
      mo_progress TYPE REF TO lcl_progress,

      mt_tools    TYPE STANDARD TABLE OF
                    zzwn00224895_ai_registry=>ty_tool
                    WITH DEFAULT KEY,

      mv_system_prompt TYPE string,
      mv_user_prompt   TYPE string,
      mv_tools         TYPE string,
      mv_run_id        TYPE string.

    METHODS:
      default_system_prompt
        RETURNING VALUE(rv_text) TYPE string,

      build_run_id
        RETURNING VALUE(rv_run_id) TYPE string,

      build_paths,

      build_header
        RETURNING VALUE(rv_header) TYPE string,

      build_services,

      activate_tools,

      tool_allowed
        IMPORTING iv_name       TYPE string
        RETURNING VALUE(rv_yes) TYPE abap_bool,

      tool_blacklisted
        IMPORTING iv_name       TYPE string
        RETURNING VALUE(rv_yes) TYPE abap_bool,

      build_user_text
        IMPORTING is_object      TYPE ty_object
        RETURNING VALUE(rv_text) TYPE string,

      process_object
        IMPORTING is_object        TYPE ty_object
                  iv_idx           TYPE i
                  iv_total         TYPE i
        RETURNING VALUE(rs_result) TYPE ty_result,

      call_with_retry
        IMPORTING iv_payload  TYPE string
                  iv_label    TYPE string
        EXPORTING ev_response TYPE string
                  ev_status   TYPE i
                  ev_error    TYPE string
                  ev_attempts TYPE i,

      read_last_answer
        IMPORTING iv_session_id TYPE char32
        EXPORTING ev_answer     TYPE string
                  ev_status     TYPE c
                  ev_http       TYPE i
                  ev_error      TYPE string.
ENDCLASS.

"----------------------------------------------------------------------
" Klassenimplementierungen
"----------------------------------------------------------------------
CLASS lcl_text IMPLEMENTATION.
  METHOD range_lows.
    FIELD-SYMBOLS:
      <ls_range> TYPE any,
      <lv_sign>  TYPE any,
      <lv_low>   TYPE any.

    LOOP AT it_range ASSIGNING <ls_range>.
      IF iv_skip_excluded = abap_true.
        ASSIGN COMPONENT 'SIGN' OF STRUCTURE <ls_range> TO <lv_sign>.
        IF sy-subrc = 0 AND <lv_sign> = 'E'.
          CONTINUE.
        ENDIF.
      ENDIF.

      ASSIGN COMPONENT 'LOW' OF STRUCTURE <ls_range> TO <lv_low>.
      IF sy-subrc = 0 AND <lv_low> IS NOT INITIAL.
        APPEND CONV string( <lv_low> ) TO rt_lines.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD join_range.
    DATA(lt_lines) = range_lows( it_range ).

    rv_text = concat_lines_of(
      table = lt_lines
      sep   = cl_abap_char_utilities=>newline ).
  ENDMETHOD.

  METHOD read_server_lines.
    DATA:
      lv_line TYPE string,
      lv_msg  TYPE string.

    IF iv_file IS INITIAL.
      RETURN.
    ENDIF.

    OPEN DATASET iv_file FOR INPUT
      IN TEXT MODE ENCODING UTF-8 MESSAGE lv_msg.

    IF sy-subrc <> 0.
      IF iv_silent = abap_true.
        RETURN.
      ENDIF.

      MESSAGE |Datei { iv_file } nicht lesbar: { lv_msg }|
        TYPE 'E'.
    ENDIF.

    DO.
      READ DATASET iv_file INTO lv_line.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      APPEND strip_cr( lv_line ) TO rt_lines.
    ENDDO.

    CLOSE DATASET iv_file.
  ENDMETHOD.

  METHOD read_server_text.
    DATA(lt_lines) = read_server_lines(
      iv_file   = iv_file
      iv_silent = iv_silent ).

    rv_text = concat_lines_of(
      table = lt_lines
      sep   = cl_abap_char_utilities=>newline ).
  ENDMETHOD.

  METHOD build_prompt.
    rv_text = join_range( it_range ).

    IF iv_file IS NOT INITIAL.
      DATA(lv_file_text) = read_server_text(
        iv_file   = iv_file
        iv_silent = iv_silent ).

      IF rv_text IS INITIAL.
        rv_text = lv_file_text.
      ELSEIF lv_file_text IS NOT INITIAL.
        rv_text = rv_text &&
          cl_abap_char_utilities=>newline &&
          lv_file_text.
      ENDIF.
    ENDIF.

    IF rv_text IS INITIAL.
      rv_text = iv_default.
    ENDIF.
  ENDMETHOD.

  METHOD replace_all.
    REPLACE ALL OCCURRENCES OF iv_old IN cv_text WITH iv_new.
  ENDMETHOD.

  METHOD strip_cr.
    DATA lv_cr TYPE c LENGTH 1.

    " Erstes Zeichen von CR_LF ist das Carriage Return.
    lv_cr   = cl_abap_char_utilities=>cr_lf.
    rv_text = iv_text.

    REPLACE ALL OCCURRENCES OF lv_cr IN rv_text WITH ``.
  ENDMETHOD.

  METHOD clean_cell.
    rv_text = iv_text.

    REPLACE ALL OCCURRENCES OF
      cl_abap_char_utilities=>cr_lf IN rv_text WITH ` `.
    REPLACE ALL OCCURRENCES OF
      cl_abap_char_utilities=>newline IN rv_text WITH ` `.
    REPLACE ALL OCCURRENCES OF
      cl_abap_char_utilities=>horizontal_tab IN rv_text WITH ` `.

    CONDENSE rv_text.
  ENDMETHOD.

  METHOD shorten.
    rv_text = iv_text.

    IF iv_length > 0 AND strlen( rv_text ) > iv_length.
      rv_text = rv_text(iv_length) && '...'.
    ENDIF.
  ENDMETHOD.

  METHOD normalize_answer.
    DATA:
      lt_lines TYPE string_table,
      lv_line  TYPE string.

    SPLIT iv_answer AT cl_abap_char_utilities=>newline
      INTO TABLE lt_lines.

    LOOP AT lt_lines INTO lv_line.
      REPLACE ALL OCCURRENCES OF
        cl_abap_char_utilities=>cr_lf IN lv_line WITH ``.

      IF lv_line IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_line CP '```*' OR lv_line = '```'.
        CONTINUE.
      ENDIF.

      IF rv_row IS INITIAL.
        rv_row = lv_line.
      ELSE.
        rv_row = rv_row && ` ` && lv_line.
      ENDIF.
    ENDLOOP.

    REPLACE ALL OCCURRENCES OF `\t`
      IN rv_row WITH cl_abap_char_utilities=>horizontal_tab.

    REPLACE ALL OCCURRENCES OF `|`
      IN rv_row WITH cl_abap_char_utilities=>horizontal_tab.

    SHIFT rv_row LEFT DELETING LEADING space.
    SHIFT rv_row RIGHT DELETING TRAILING space.

    WHILE rv_row CP
      cl_abap_char_utilities=>horizontal_tab && '*'.
      SHIFT rv_row LEFT BY 1 PLACES.
    ENDWHILE.

    WHILE rv_row CP
      '*' && cl_abap_char_utilities=>horizontal_tab.
      DATA(lv_len) = strlen( rv_row ).
      IF lv_len > 0.
        lv_len = lv_len - 1.
        rv_row = rv_row(lv_len).
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.

  METHOD count_columns.
    DATA lt_cells TYPE string_table.

    IF iv_row IS INITIAL.
      rv_cols = 0.
      RETURN.
    ENDIF.

    SPLIT iv_row AT cl_abap_char_utilities=>horizontal_tab
      INTO TABLE lt_cells.

    rv_cols = lines( lt_cells ).
  ENDMETHOD.

  METHOD duration_text.
    DATA:
      lv_seconds TYPE i,
      lv_days    TYPE i,
      lv_hours   TYPE i,
      lv_minutes TYPE i.

    lv_seconds = iv_seconds.
    IF lv_seconds < 0.
      lv_seconds = 0.
    ENDIF.

    lv_days    = lv_seconds DIV 86400.
    lv_seconds = lv_seconds MOD 86400.
    lv_hours   = lv_seconds DIV 3600.
    lv_seconds = lv_seconds MOD 3600.
    lv_minutes = lv_seconds DIV 60.
    lv_seconds = lv_seconds MOD 60.

    rv_text =
      |{ lv_days }d { lv_hours }h { lv_minutes }m { lv_seconds }s|.
  ENDMETHOD.

  METHOD item_key.
    IF iv_kind = gc_kind_prompt.
      rv_key = |{ gc_item_prompt }:{ iv_obj_name }|.
    ELSE.
      rv_key = |{ iv_object }:{ iv_obj_name }|.
    ENDIF.
  ENDMETHOD.

  METHOD item_label.
    IF is_object-kind <> gc_kind_prompt.
      rv_text = |{ is_object-object }:{ is_object-obj_name }|.
      RETURN.
    ENDIF.

    IF is_object-tpl_values IS NOT INITIAL.
      rv_text = |Prompt { is_object-prompt_no } [{ is_object-tpl_values }]|.
    ELSE.
      DATA(lv_excerpt) = shorten(
        iv_text   = clean_cell( is_object-prompt_text )
        iv_length = 60 ).

      rv_text = |Prompt { is_object-prompt_no } '{ lv_excerpt }'|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_prompt_file IMPLEMENTATION.
  METHOD read_server_lines.
    IF iv_file IS INITIAL.
      RETURN.
    ENDIF.

    IF is_xlsx( iv_file ) = abap_true.
      rt_lines = xlsx_to_lines(
        iv_name = iv_file
        iv_data = read_server_binary( iv_file ) ).
    ELSE.
      rt_lines = lcl_text=>read_server_lines( iv_file ).
    ENDIF.
  ENDMETHOD.

  METHOD read_frontend_lines.
    DATA:
      lt_files  TYPE filetable,
      lv_rc     TYPE i,
      lv_action TYPE i,
      lt_data   TYPE solix_tab,
      lv_length TYPE i.

    IF sy-batch = abap_true.
      RETURN.
    ENDIF.

    cl_gui_frontend_services=>file_open_dialog(
      EXPORTING
        window_title   = 'Promptliste importieren'
        file_filter    = 'Text/CSV (*.txt;*.csv)|*.txt;*.csv|' &&
                         'Excel (*.xlsx)|*.xlsx|Alle Dateien (*.*)|*.*|'
        multiselection = abap_false
      CHANGING
        file_table     = lt_files
        rc             = lv_rc
        user_action    = lv_action
      EXCEPTIONS
        OTHERS         = 1 ).

    IF sy-subrc <> 0
    OR lv_action <> cl_gui_frontend_services=>action_ok
    OR lt_files IS INITIAL.
      RETURN.
    ENDIF.

    READ TABLE lt_files INDEX 1 INTO DATA(ls_file).
    DATA(lv_file) = CONV string( ls_file-filename ).

    cl_gui_frontend_services=>gui_upload(
      EXPORTING
        filename   = lv_file
        filetype   = 'BIN'
      IMPORTING
        filelength = lv_length
      CHANGING
        data_tab   = lt_data
      EXCEPTIONS
        OTHERS     = 1 ).

    IF sy-subrc <> 0.
      MESSAGE |Datei { lv_file } konnte nicht hochgeladen werden.|
        TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    DATA(lv_data) = cl_bcs_convert=>solix_to_xstring(
      it_solix = lt_data
      iv_size  = lv_length ).

    rt_lines = lines_from_xstring(
      iv_name = lv_file
      iv_data = lv_data ).
  ENDMETHOD.

  METHOD is_xlsx.
    DATA(lv_name) = to_lower( iv_name ).

    rv_yes = xsdbool( lv_name CP '*.xlsx' OR lv_name CP '*.xlsm' ).
  ENDMETHOD.

  METHOD lines_from_xstring.
    IF is_xlsx( iv_name ) = abap_true.
      rt_lines = xlsx_to_lines(
        iv_name = iv_name
        iv_data = iv_data ).
    ELSE.
      rt_lines = text_to_lines( iv_data ).
    ENDIF.
  ENDMETHOD.

  METHOD xlsx_to_lines.
    DATA:
      lo_excel  TYPE REF TO cl_fdt_xl_spreadsheet,
      lt_sheets TYPE if_fdt_doc_spreadsheet=>t_worksheet_names,
      lr_rows   TYPE REF TO data,
      lv_line   TYPE string,
      lv_cell   TYPE string.

    FIELD-SYMBOLS:
      <lt_rows> TYPE STANDARD TABLE,
      <ls_row>  TYPE any,
      <lv_cell> TYPE any.

    TRY.
        lo_excel = NEW cl_fdt_xl_spreadsheet(
          document_name = iv_name
          xdocument     = iv_data ).

        lo_excel->if_fdt_doc_spreadsheet~get_worksheet_names(
          IMPORTING worksheet_names = lt_sheets ).

        " Es wird nur das erste Tabellenblatt gelesen.
        READ TABLE lt_sheets INDEX 1 INTO DATA(lv_sheet).
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.

        lr_rows = lo_excel->if_fdt_doc_spreadsheet~get_itab_from_worksheet(
          lv_sheet ).
      CATCH cx_fdt_excel_core INTO DATA(lx_excel).
        MESSAGE |Excel-Datei { iv_name } nicht lesbar: { lx_excel->get_text( ) }|
          TYPE 'E'.
    ENDTRY.

    IF lr_rows IS NOT BOUND.
      RETURN.
    ENDIF.

    ASSIGN lr_rows->* TO <lt_rows>.

    " Alle gefüllten Zellen einer Zeile werden mit Leerzeichen zu einem
    " Prompt verbunden; damit reicht Spalte A, weitere Spalten sind erlaubt.
    LOOP AT <lt_rows> ASSIGNING <ls_row>.
      CLEAR lv_line.

      DO.
        ASSIGN COMPONENT sy-index OF STRUCTURE <ls_row> TO <lv_cell>.
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.

        lv_cell = <lv_cell>.
        CONDENSE lv_cell.

        IF lv_cell IS INITIAL.
          CONTINUE.
        ENDIF.

        IF lv_line IS INITIAL.
          lv_line = lv_cell.
        ELSE.
          lv_line = |{ lv_line } { lv_cell }|.
        ENDIF.
      ENDDO.

      APPEND lv_line TO rt_lines.
    ENDLOOP.
  ENDMETHOD.

  METHOD text_to_lines.
    DATA:
      lv_data       TYPE xstring,
      lv_text       TYPE string,
      lv_bom_length TYPE i,
      lv_codepage   TYPE abap_encoding VALUE '4110'.

    lv_data = iv_data.

    " Byte Order Mark auswerten: UTF-8 (Standard), UTF-16LE, UTF-16BE.
    IF starts_with( iv_data   = lv_data
                    iv_prefix = cl_abap_char_utilities=>byte_order_mark_utf8 ) = abap_true.
      lv_bom_length = 3.
    ELSEIF starts_with( iv_data   = lv_data
                        iv_prefix = cl_abap_char_utilities=>byte_order_mark_little ) = abap_true.
      lv_bom_length = 2.
      lv_codepage   = '4103'.
    ELSEIF starts_with( iv_data   = lv_data
                        iv_prefix = cl_abap_char_utilities=>byte_order_mark_big ) = abap_true.
      lv_bom_length = 2.
      lv_codepage   = '4102'.
    ENDIF.

    IF lv_bom_length > 0.
      IF xstrlen( lv_data ) > lv_bom_length.
        lv_data = lv_data+lv_bom_length.
      ELSE.
        CLEAR lv_data.
      ENDIF.
    ENDIF.

    TRY.
        lv_text = decode(
          iv_data     = lv_data
          iv_codepage = lv_codepage
          iv_strict   = abap_true ).
      CATCH cx_sy_conversion_codepage
            cx_sy_codepage_converter_init
            cx_parameter_invalid.
        " Kein gültiges UTF-8/UTF-16: Windows-1252 (SAP-Codepage 1160)
        " als Rückfall, nicht darstellbare Zeichen werden zu '#'.
        TRY.
            lv_text = decode(
              iv_data     = lv_data
              iv_codepage = '1160'
              iv_strict   = abap_false ).
          CATCH cx_sy_conversion_codepage
                cx_sy_codepage_converter_init
                cx_parameter_invalid.
            MESSAGE 'Textdatei konnte nicht dekodiert werden.' TYPE 'E'.
        ENDTRY.
    ENDTRY.

    SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE rt_lines.
  ENDMETHOD.

  METHOD decode.
    DATA(lo_converter) = cl_abap_conv_in_ce=>create(
      encoding    = iv_codepage
      replacement = '#'
      ignore_cerr = xsdbool( iv_strict = abap_false ) ).

    lo_converter->convert(
      EXPORTING input = iv_data
      IMPORTING data  = rv_text ).
  ENDMETHOD.

  METHOD starts_with.
    DATA(lv_length) = xstrlen( iv_prefix ).

    IF lv_length = 0 OR xstrlen( iv_data ) < lv_length.
      rv_yes = abap_false.
      RETURN.
    ENDIF.

    rv_yes = xsdbool( iv_data(lv_length) = iv_prefix ).
  ENDMETHOD.

  METHOD read_server_binary.
    DATA lv_msg TYPE string.

    OPEN DATASET iv_file FOR INPUT IN BINARY MODE MESSAGE lv_msg.

    IF sy-subrc <> 0.
      MESSAGE |Datei { iv_file } nicht lesbar: { lv_msg }| TYPE 'E'.
    ENDIF.

    READ DATASET iv_file INTO rv_data.
    CLOSE DATASET iv_file.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_template IMPLEMENTATION.
  METHOD read_template.
    rv_text = lcl_text=>build_prompt(
      it_range   = s_tpl[]
      iv_file    = CONV string( p_tplfil )
      iv_default = ``
      iv_silent  = iv_silent ).
  ENDMETHOD.

  METHOD find_placeholders.
    DATA lt_results TYPE match_result_tab.

    FIND ALL OCCURRENCES OF REGEX gc_placeholder_regex
      IN iv_text RESULTS lt_results.

    " Reihenfolge des ersten Auftretens bestimmt die Zuordnung zu den
    " Wertefeldern S_TV01..S_TV10.
    LOOP AT lt_results INTO DATA(ls_result).
      READ TABLE ls_result-submatches INDEX 1 INTO DATA(ls_submatch).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      DATA(lv_name) = iv_text+ls_submatch-offset(ls_submatch-length).

      IF NOT line_exists( rt_names[ table_line = lv_name ] ).
        APPEND lv_name TO rt_names.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD slot_values.
    CASE iv_slot.
      WHEN 1.
        rt_values = lcl_text=>range_lows( it_range = s_tv01[] iv_skip_excluded = abap_true ).
      WHEN 2.
        rt_values = lcl_text=>range_lows( it_range = s_tv02[] iv_skip_excluded = abap_true ).
      WHEN 3.
        rt_values = lcl_text=>range_lows( it_range = s_tv03[] iv_skip_excluded = abap_true ).
      WHEN 4.
        rt_values = lcl_text=>range_lows( it_range = s_tv04[] iv_skip_excluded = abap_true ).
      WHEN 5.
        rt_values = lcl_text=>range_lows( it_range = s_tv05[] iv_skip_excluded = abap_true ).
      WHEN 6.
        rt_values = lcl_text=>range_lows( it_range = s_tv06[] iv_skip_excluded = abap_true ).
      WHEN 7.
        rt_values = lcl_text=>range_lows( it_range = s_tv07[] iv_skip_excluded = abap_true ).
      WHEN 8.
        rt_values = lcl_text=>range_lows( it_range = s_tv08[] iv_skip_excluded = abap_true ).
      WHEN 9.
        rt_values = lcl_text=>range_lows( it_range = s_tv09[] iv_skip_excluded = abap_true ).
      WHEN 10.
        rt_values = lcl_text=>range_lows( it_range = s_tv10[] iv_skip_excluded = abap_true ).
    ENDCASE.
  ENDMETHOD.

  METHOD expand.
    DATA:
      lt_current TYPE tt_expansion,
      lt_next    TYPE tt_expansion,
      lv_pattern TYPE string.

    APPEND VALUE #( text = iv_template ) TO lt_current.

    " Kartesisches Produkt über alle Platzhalter: jeder Platzhalter
    " vervielfacht die bisherigen Prompts mit seinen Werten.
    LOOP AT it_names INTO DATA(lv_name).
      DATA(lv_slot)   = sy-tabix.
      DATA(lt_values) = slot_values( lv_slot ).

      IF lt_values IS INITIAL.
        MESSAGE |Platzhalter %{ lv_name }% (Wertefeld { lv_slot }) hat keine Werte.|
          TYPE 'E'.
      ENDIF.

      IF lines( lt_current ) * lines( lt_values ) > gc_max_prompts.
        MESSAGE |Zu viele Kombinationen; maximal { gc_max_prompts } Prompts.|
          TYPE 'E'.
      ENDIF.

      lv_pattern = |%{ lv_name }%|.
      CLEAR lt_next.

      LOOP AT lt_current INTO DATA(ls_current).
        LOOP AT lt_values INTO DATA(lv_value).
          DATA(ls_next) = ls_current.

          REPLACE ALL OCCURRENCES OF lv_pattern
            IN ls_next-text WITH lv_value.

          IF ls_next-value_text IS INITIAL.
            ls_next-value_text = |{ lv_name }={ lv_value }|.
          ELSE.
            ls_next-value_text = |{ ls_next-value_text }; { lv_name }={ lv_value }|.
          ENDIF.

          APPEND ls_next TO lt_next.
        ENDLOOP.
      ENDLOOP.

      lt_current = lt_next.
    ENDLOOP.

    rt_prompts = lt_current.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_object_resolver IMPLEMENTATION.
  METHOD get_objects.
    DATA lv_func_requested TYPE abap_bool.

    lv_func_requested = xsdbool(
      s_objtyp[] IS INITIAL OR
      line_exists( s_objtyp[
        sign   = 'I'
        option = 'EQ'
        low    = 'FUNC' ] ) ).

    IF lv_func_requested = abap_true.
      add_functions( CHANGING ct_objects = rt_objects ).
    ENDIF.

    " FUNC darf nicht über TADIR gesucht werden.
    " Andere Repositorytypen weiterhin normal aus TADIR lesen.
    add_from_tadir( CHANGING ct_objects = rt_objects ).
    add_from_file( CHANGING ct_objects = rt_objects ).

    SORT rt_objects BY object obj_name.
    DELETE ADJACENT DUPLICATES FROM rt_objects
      COMPARING object obj_name.

    IF p_maxobj > 0 AND lines( rt_objects ) > p_maxobj.
      DATA(lv_from) = p_maxobj + 1.
      DELETE rt_objects FROM lv_from.
    ENDIF.
  ENDMETHOD.

  METHOD add_from_tadir.
    DATA lr_objtyp LIKE s_objtyp[].

    lr_objtyp = s_objtyp[].

    " FUNC ist kein reguläres TADIR-R3TR-Objekt.
    DELETE lr_objtyp WHERE low = 'FUNC'.

    IF lr_objtyp IS INITIAL.
      RETURN.
    ENDIF.

    SELECT object,
           obj_name,
           devclass,
           author
      FROM tadir
      WHERE object   IN @lr_objtyp
        AND obj_name IN @s_objnam
        AND devclass IN @s_devc
        AND author   IN @s_author
        AND delflag  = @space
      INTO TABLE @DATA(lt_tadir).

    LOOP AT lt_tadir INTO DATA(ls_tadir).
      append_unique(
        EXPORTING
          is_object  = CORRESPONDING #( ls_tadir )
        CHANGING
          ct_objects = ct_objects ).
    ENDLOOP.
  ENDMETHOD.

  METHOD add_functions.
    TYPES:
      BEGIN OF ty_function,
        funcname TYPE tfdir-funcname,
        pname    TYPE tfdir-pname,
        include  TYPE tfdir-include,
        fmode    TYPE tfdir-fmode,
        utask    TYPE tfdir-utask,
      END OF ty_function.

    DATA:
      lt_functions TYPE STANDARD TABLE OF ty_function WITH EMPTY KEY,
      lv_match     TYPE abap_bool,
      lv_group     TYPE rs38l-area,
      lv_devclass  TYPE tadir-devclass,
      lv_author    TYPE tadir-author.

    " Zuerst nur die grundsätzlich relevanten Namensräume lesen.
    " Damit können fremde Objekte wie /THA/* gar nicht in die Liste gelangen.
    SELECT funcname,
           pname,
           include,
           fmode,
           utask
      FROM tfdir
      WHERE funcname LIKE '/WUE/%'
         OR funcname LIKE '/W4E/%'
         OR funcname LIKE 'Z%'
      INTO TABLE @lt_functions.

    LOOP AT lt_functions INTO DATA(ls_function).
      CLEAR lv_match.

      " Die Datenbank-Vorauswahl wird nochmals gegen den tatsächlichen
      " Selektionsbereich geprüft. Das berücksichtigt I/E und EQ/CP korrekt.
      IF s_objnam[] IS INITIAL.
        lv_match = abap_true.
      ELSE.
        IF ls_function-funcname IN s_objnam.
          lv_match = abap_true.
        ENDIF.
      ENDIF.

      IF lv_match = abap_false.
        CONTINUE.
      ENDIF.

      SELECT SINGLE funcname,
                    area,
                    active,
                    generated
        FROM enlfdir
        WHERE funcname = @ls_function-funcname
        INTO @DATA(ls_enlfdir).

      IF sy-subrc <> 0.
        CLEAR ls_enlfdir.
      ENDIF.

      CLEAR:
        lv_group,
        lv_devclass,
        lv_author.

      IF ls_enlfdir-area IS NOT INITIAL.
        lv_group = ls_enlfdir-area.
      ELSE.
        " Fallback nur, wenn ENLFDIR-AREA fehlt.
        lv_group = ls_function-pname.
        REPLACE FIRST OCCURRENCE OF 'SAPL'
          IN lv_group WITH ''.
      ENDIF.

      " Paket und Autor werden über das echte FUGR-Repositoryobjekt gelesen.
      SELECT SINGLE devclass,
                    author
        FROM tadir
        WHERE pgmid    = 'R3TR'
          AND object   = 'FUGR'
          AND obj_name = @lv_group
          AND delflag  = @space
        INTO (@lv_devclass, @lv_author).

      " Paketfilter anwenden.
      IF s_devc[] IS NOT INITIAL AND
         lv_devclass NOT IN s_devc.
        CONTINUE.
      ENDIF.

      " Autorenfilter anwenden.
      IF s_author[] IS NOT INITIAL AND
         lv_author NOT IN s_author.
        CONTINUE.
      ENDIF.

      append_unique(
        EXPORTING
          is_object  = VALUE ty_object(
            object       = 'FUNC'
            obj_name     = ls_function-funcname
            devclass     = lv_devclass
            author       = lv_author
            funcname     = ls_function-funcname
            func_group   = lv_group
            func_pool    = ls_function-pname
            func_include = ls_function-include
            fmode        = ls_function-fmode
            utask        = ls_function-utask
            generated    = ls_enlfdir-generated )
        CHANGING
          ct_objects = ct_objects ).
    ENDLOOP.
  ENDMETHOD.

  METHOD add_from_file.
    DATA:
      lv_line TYPE string,
      lv_type TYPE string,
      lv_name TYPE string,
      lv_msg  TYPE string.

    IF p_infile IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_file) = CONV string( p_infile ).

    OPEN DATASET lv_file FOR INPUT
      IN TEXT MODE ENCODING UTF-8 MESSAGE lv_msg.

    IF sy-subrc <> 0.
      MESSAGE |Objektdatei { lv_file } nicht lesbar: { lv_msg }|
        TYPE 'E'.
    ENDIF.

    DO.
      READ DATASET lv_file INTO lv_line.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      CONDENSE lv_line.

      IF lv_line IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_line(1) = '#'.
        CONTINUE.
      ENDIF.

      CLEAR:
        lv_type,
        lv_name.

      SPLIT lv_line AT ':' INTO lv_type lv_name.

      IF lv_name IS INITIAL.
        lv_name = lv_type.
        CLEAR lv_type.
      ENDIF.

      TRANSLATE lv_type TO UPPER CASE.
      TRANSLATE lv_name TO UPPER CASE.
      CONDENSE:
        lv_type,
        lv_name.

      IF s_objnam[] IS NOT INITIAL AND
         lv_name NOT IN s_objnam.
        CONTINUE.
      ENDIF.

      DATA(ls_object) = VALUE ty_object(
        object   = COND #(
          WHEN lv_type IS INITIAL THEN 'PROG'
          ELSE lv_type )
        obj_name = lv_name ).

      enrich( CHANGING cs_object = ls_object ).

      append_unique(
        EXPORTING is_object  = ls_object
        CHANGING  ct_objects = ct_objects ).
    ENDDO.

    CLOSE DATASET lv_file.
  ENDMETHOD.

  METHOD enrich.
    IF cs_object-object = 'FUNC'.
      DATA lv_funcname TYPE tfdir-funcname.

      lv_funcname = cs_object-obj_name.

      SELECT SINGLE *
        FROM tfdir
        WHERE funcname = @lv_funcname
        INTO @DATA(ls_tfdir).

      IF sy-subrc <> 0.
        RETURN.
      ENDIF.

      SELECT SINGLE *
        FROM enlfdir
        WHERE funcname = @lv_funcname
        INTO @DATA(ls_enlfdir).

      cs_object-object       = 'FUNC'.
      cs_object-obj_name     = ls_tfdir-funcname.
      cs_object-funcname     = ls_tfdir-funcname.
      cs_object-func_pool    = ls_tfdir-pname.
      cs_object-func_include = ls_tfdir-include.
      cs_object-fmode        = ls_tfdir-fmode.
      cs_object-utask        = ls_tfdir-utask.
      cs_object-func_group   = ls_enlfdir-area.
      cs_object-generated    = ls_enlfdir-generated.

      IF cs_object-func_group IS INITIAL.
        cs_object-func_group = ls_tfdir-pname.
        REPLACE FIRST OCCURRENCE OF 'SAPL'
          IN cs_object-func_group WITH ''.
      ENDIF.

      SELECT SINGLE devclass,
                    author
        FROM tadir
        WHERE pgmid    = 'R3TR'
          AND object   = 'FUGR'
          AND obj_name = @cs_object-func_group
          AND delflag  = @space
        INTO (@cs_object-devclass, @cs_object-author).

      RETURN.
    ENDIF.

    SELECT SINGLE object,
                  obj_name,
                  devclass,
                  author
      FROM tadir
      WHERE object   = @cs_object-object
        AND obj_name = @cs_object-obj_name
        AND delflag  = @space
      INTO @DATA(ls_tadir).

    IF sy-subrc = 0.
      cs_object = CORRESPONDING #( ls_tadir ).
      RETURN.
    ENDIF.

    IF cs_object-object IS INITIAL OR
       cs_object-object = 'PROG'.

      SELECT SINGLE object,
                    obj_name,
                    devclass,
                    author
        FROM tadir
        WHERE obj_name = @cs_object-obj_name
          AND delflag  = @space
        INTO @ls_tadir.

      IF sy-subrc = 0.
        cs_object = CORRESPONDING #( ls_tadir ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD append_unique.
    READ TABLE ct_objects TRANSPORTING NO FIELDS
      WITH KEY
        object   = is_object-object
        obj_name = is_object-obj_name.

    IF sy-subrc <> 0 AND is_object-obj_name IS NOT INITIAL.
      DATA(ls_object) = is_object.
      ls_object-kind = gc_kind_object.
      APPEND ls_object TO ct_objects.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_prompt_resolver IMPLEMENTATION.
  METHOD get_items.
    IF p_tplmod = abap_true.
      add_from_template( CHANGING ct_items = rt_items ).
    ELSE.
      add_from_list( CHANGING ct_items = rt_items ).
    ENDIF.

    IF p_maxobj > 0 AND lines( rt_items ) > p_maxobj.
      DATA(lv_from) = p_maxobj + 1.
      DELETE rt_items FROM lv_from.
    ENDIF.

    LOOP AT rt_items ASSIGNING FIELD-SYMBOL(<ls_item>).
      <ls_item>-prompt_no = sy-tabix.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_from_list.
    " Einträge mit SIGN = 'E' (Tab "Einzelwerte ausschließen") gelten als
    " deaktiviert und werden nicht gesendet.
    DATA(lt_lines) = lcl_text=>range_lows(
      it_range         = s_prm[]
      iv_skip_excluded = abap_true ).

    IF p_prmfil IS NOT INITIAL.
      DATA(lt_file_lines) = lcl_prompt_file=>read_server_lines(
        CONV string( p_prmfil ) ).
      APPEND LINES OF lt_file_lines TO lt_lines.
    ENDIF.

    LOOP AT lt_lines INTO DATA(lv_line).
      DATA(lv_text)  = lcl_text=>strip_cr( lv_line ).
      DATA(lv_check) = condense( lv_text ).

      " Leere Zeilen und Kommentarzeilen (#) werden übersprungen.
      IF lv_check IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_check(1) = '#'.
        CONTINUE.
      ENDIF.

      append_prompt(
        EXPORTING
          iv_text   = lv_text
          iv_values = ``
        CHANGING
          ct_items  = ct_items ).
    ENDLOOP.
  ENDMETHOD.

  METHOD add_from_template.
    DATA(lv_template) = lcl_template=>read_template( ).

    IF lv_template IS INITIAL.
      MESSAGE 'Template-Modus aktiv, aber kein Template erfasst.' TYPE 'E'.
    ENDIF.

    DATA(lt_names) = lcl_template=>find_placeholders( lv_template ).

    IF lines( lt_names ) > gc_max_slots.
      MESSAGE |Template enthält { lines( lt_names ) } Platzhalter; | &&
              |maximal { gc_max_slots } werden unterstützt.|
        TYPE 'E'.
    ENDIF.

    DATA(lt_expanded) = lcl_template=>expand(
      iv_template = lv_template
      it_names    = lt_names ).

    LOOP AT lt_expanded INTO DATA(ls_expanded).
      append_prompt(
        EXPORTING
          iv_text   = ls_expanded-text
          iv_values = ls_expanded-value_text
        CHANGING
          ct_items  = ct_items ).
    ENDLOOP.
  ENDMETHOD.

  METHOD append_prompt.
    DATA(lv_key) = prompt_key( iv_text ).

    " Identische Prompts werden wie identische Objekte nur einmal verarbeitet.
    IF line_exists( mt_seen[ table_line = lv_key ] ).
      RETURN.
    ENDIF.

    INSERT CONV string( lv_key ) INTO TABLE mt_seen.

    APPEND VALUE ty_object(
      kind        = gc_kind_prompt
      obj_name    = lv_key
      prompt_key  = lv_key
      prompt_text = iv_text
      tpl_values  = iv_values ) TO ct_items.
  ENDMETHOD.

  METHOD prompt_key.
    DATA lv_hash TYPE string.

    " SHA1 des Prompttexts (40 Hex-Zeichen) dient als stabiler Schlüssel
    " für die Fortsetzung, unabhängig von der Position in der Liste.
    TRY.
        cl_abap_message_digest=>calculate_hash_for_char(
          EXPORTING
            if_algorithm  = 'SHA1'
            if_data       = iv_text
          IMPORTING
            ef_hashstring = lv_hash ).
      CATCH cx_abap_message_digest.
        CLEAR lv_hash.
    ENDTRY.

    IF lv_hash IS INITIAL.
      mv_counter = mv_counter + 1.
      lv_hash = |NOHASH{ mv_counter }|.
    ENDIF.

    rv_key = lv_hash.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_screen IMPLEMENTATION.
  METHOD adjust.
    DATA lt_names TYPE string_table.

    DATA(lv_prompt_mode)   = p_mprm.
    DATA(lv_template_mode) = xsdbool( p_mprm = abap_true AND p_tplmod = abap_true ).

    IF lv_template_mode = abap_true.
      lt_names = lcl_template=>find_placeholders(
        lcl_template=>read_template( iv_silent = abap_true ) ).
    ENDIF.

    " Beschriftung der Wertefelder = Platzhalter in Reihenfolge des Templates.
    DO gc_max_slots TIMES.
      DATA(lv_slot) = sy-index.

      READ TABLE lt_names INDEX lv_slot INTO DATA(lv_name).
      IF sy-subrc = 0.
        set_slot_label( iv_slot = lv_slot iv_text = |%{ lv_name }%| ).
      ELSE.
        set_slot_label( iv_slot = lv_slot iv_text = `` ).
      ENDIF.
    ENDDO.

    LOOP AT SCREEN.
      CASE screen-group1.
        WHEN 'OBJ'.
          IF lv_prompt_mode = abap_true.
            screen-input = 0.
          ENDIF.

        WHEN 'PRA'.
          IF lv_prompt_mode = abap_false.
            screen-input = 0.
          ENDIF.

        WHEN 'PRM'.
          IF lv_prompt_mode = abap_false OR p_tplmod = abap_true.
            screen-input = 0.
          ENDIF.

        WHEN 'TPL'.
          IF lv_template_mode = abap_false.
            screen-input = 0.
          ENDIF.

        WHEN OTHERS.
          " Wertefelder V01..V10 nur für tatsächlich vorhandene Platzhalter.
          IF screen-group1(1) = 'V' AND screen-group1+1(2) CO '0123456789'.
            IF lv_template_mode = abap_false
            OR CONV i( screen-group1+1(2) ) > lines( lt_names ).
              screen-active = 0.
            ENDIF.
          ENDIF.
      ENDCASE.

      MODIFY SCREEN.
    ENDLOOP.
  ENDMETHOD.

  METHOD set_slot_label.
    CASE iv_slot.
      WHEN 1.
        gv_l01 = iv_text.
      WHEN 2.
        gv_l02 = iv_text.
      WHEN 3.
        gv_l03 = iv_text.
      WHEN 4.
        gv_l04 = iv_text.
      WHEN 5.
        gv_l05 = iv_text.
      WHEN 6.
        gv_l06 = iv_text.
      WHEN 7.
        gv_l07 = iv_text.
      WHEN 8.
        gv_l08 = iv_text.
      WHEN 9.
        gv_l09 = iv_text.
      WHEN 10.
        gv_l10 = iv_text.
    ENDCASE.
  ENDMETHOD.

  METHOD edit_range.
    DATA:
      lt_text  TYPE catsxt_longtext_itab,
      lv_title TYPE sy-title.

    FIELD-SYMBOLS:
      <ls_range>  TYPE any,
      <lv_sign>   TYPE any,
      <lv_option> TYPE any,
      <lv_low>    TYPE any.

    IF sy-batch = abap_true.
      RETURN.
    ENDIF.

    LOOP AT ct_range ASSIGNING <ls_range>.
      ASSIGN COMPONENT 'LOW' OF STRUCTURE <ls_range> TO <lv_low>.
      IF sy-subrc = 0.
        APPEND CONV string( <lv_low> ) TO lt_text.
      ENDIF.
    ENDLOOP.

    lv_title = iv_title.

    CALL FUNCTION 'CATSXT_SIMPLE_TEXT_EDITOR'
      EXPORTING
        im_title = lv_title
      CHANGING
        ch_text  = lt_text.

    CLEAR ct_range.

    LOOP AT lt_text INTO DATA(lv_line).
      APPEND INITIAL LINE TO ct_range ASSIGNING <ls_range>.

      ASSIGN COMPONENT 'SIGN' OF STRUCTURE <ls_range> TO <lv_sign>.
      IF sy-subrc = 0.
        <lv_sign> = 'I'.
      ENDIF.

      ASSIGN COMPONENT 'OPTION' OF STRUCTURE <ls_range> TO <lv_option>.
      IF sy-subrc = 0.
        <lv_option> = 'EQ'.
      ENDIF.

      ASSIGN COMPONENT 'LOW' OF STRUCTURE <ls_range> TO <lv_low>.
      IF sy-subrc = 0.
        <lv_low> = lv_line.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD import_prompt_list.
    DATA lv_truncated TYPE i.

    DATA(lt_lines) = lcl_prompt_file=>read_frontend_lines( ).

    IF lt_lines IS INITIAL.
      RETURN.
    ENDIF.

    CLEAR s_prm[].

    LOOP AT lt_lines INTO DATA(lv_line).
      DATA(lv_text) = lcl_text=>strip_cr( lv_line ).

      IF condense( lv_text ) IS INITIAL.
        CONTINUE.
      ENDIF.

      IF strlen( lv_text ) > gc_prompt_line_length.
        lv_truncated = lv_truncated + 1.
      ENDIF.

      APPEND VALUE #(
        sign   = 'I'
        option = 'EQ'
        low    = CONV ty_prompt_line( lv_text ) ) TO s_prm.
    ENDLOOP.

    IF lv_truncated > 0.
      MESSAGE |{ lines( s_prm[] ) } Prompts importiert; { lv_truncated } Zeilen | &&
              |auf { gc_prompt_line_length } Zeichen gekürzt | &&
              |(lange Prompts besser als Serverdatei angeben).|
        TYPE 'S' DISPLAY LIKE 'W'.
    ELSE.
      MESSAGE |{ lines( s_prm[] ) } Prompts importiert.| TYPE 'S'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_tsv_writer IMPLEMENTATION.
  METHOD constructor.
    mv_result_file = iv_result_file.
    mv_log_file    = iv_log_file.
  ENDMETHOD.

  METHOD initialize.
    DATA lv_exists TYPE abap_bool.

    OPEN DATASET mv_result_file FOR INPUT
      IN TEXT MODE ENCODING UTF-8.

    IF sy-subrc = 0.
      lv_exists = abap_true.
      CLOSE DATASET mv_result_file.
    ENDIF.

    IF iv_resume = abap_true AND lv_exists = abap_true.
      load_done( ).
      write_log(
        |Vorhandene Ergebnisdatei wird fortgesetzt; | &&
        |{ lines( mt_done ) } Einträge bereits erledigt.| ).
      RETURN.
    ENDIF.

    OPEN DATASET mv_result_file FOR OUTPUT
      IN TEXT MODE ENCODING UTF-8 WITH UNIX LINEFEED.

    IF sy-subrc <> 0.
      MESSAGE |Ergebnisdatei { mv_result_file } nicht anlegbar.|
        TYPE 'E'.
    ENDIF.

    TRANSFER iv_header TO mv_result_file.
    CLOSE DATASET mv_result_file.

    OPEN DATASET mv_log_file FOR OUTPUT
      IN TEXT MODE ENCODING UTF-8 WITH UNIX LINEFEED.

    IF sy-subrc = 0.
      CLOSE DATASET mv_log_file.
    ENDIF.
  ENDMETHOD.

  METHOD append_line.
    OPEN DATASET iv_file FOR APPENDING
      IN TEXT MODE ENCODING UTF-8 WITH UNIX LINEFEED.

    IF sy-subrc <> 0.
      MESSAGE |Datei { iv_file } nicht schreibbar.|
        TYPE 'E'.
    ENDIF.

    TRANSFER iv_line TO iv_file.
    CLOSE DATASET iv_file.
  ENDMETHOD.

  METHOD write_result.
    DATA lv_row TYPE string.

    DATA(lv_tab) = cl_abap_char_utilities=>horizontal_tab.

    " Schlüsselspalten je Modus; die ersten beiden Spalten bilden immer
    " den Fortsetzungsschlüssel (siehe LOAD_DONE).
    IF is_result-kind = gc_kind_prompt.
      lv_row =
        |{ gc_item_prompt }{ lv_tab }| &&
        |{ is_result-prompt_key }{ lv_tab }| &&
        |{ is_result-prompt_no }{ lv_tab }| &&
        |{ lcl_text=>clean_cell( is_result-tpl_values ) }{ lv_tab }| &&
        |{ lcl_text=>clean_cell( is_result-prompt_text ) }{ lv_tab }|.
    ELSE.
      lv_row =
        |{ is_result-object }{ lv_tab }| &&
        |{ is_result-obj_name }{ lv_tab }| &&
        |{ is_result-devclass }{ lv_tab }| &&
        |{ is_result-author }{ lv_tab }|.
    ENDIF.

    lv_row = lv_row &&
      |{ is_result-status }{ lv_tab }| &&
      |{ is_result-session_id }{ lv_tab }| &&
      |{ is_result-attempts }{ lv_tab }| &&
      |{ is_result-steps }{ lv_tab }| &&
      |{ is_result-duration_s }{ lv_tab }| &&
      |{ is_result-http_status }{ lv_tab }| &&
      |{ lcl_text=>clean_cell( is_result-error_text ) }{ lv_tab }| &&
      is_result-output_row.

    append_line(
      iv_file = mv_result_file
      iv_line = lv_row ).

    DATA(lv_key) = lcl_text=>item_key(
      iv_kind     = is_result-kind
      iv_object   = is_result-object
      iv_obj_name = is_result-obj_name ).

    INSERT lv_key INTO TABLE mt_done.
  ENDMETHOD.

  METHOD write_log.
    append_line(
      iv_file = mv_log_file
      iv_line = |{ sy-datum } { sy-uzeit } { iv_text }| ).
  ENDMETHOD.

  METHOD load_done.
    DATA:
      lv_line TYPE string,
      lt_cell TYPE string_table,
      lv_key  TYPE string.

    OPEN DATASET mv_result_file FOR INPUT
      IN TEXT MODE ENCODING UTF-8.

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DO.
      READ DATASET mv_result_file INTO lv_line.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      SPLIT lv_line AT cl_abap_char_utilities=>horizontal_tab
        INTO TABLE lt_cell.

      IF lines( lt_cell ) < 2.
        CONTINUE.
      ENDIF.

      READ TABLE lt_cell INDEX 1 INTO DATA(lv_type).
      READ TABLE lt_cell INDEX 2 INTO DATA(lv_name).

      " Kopfzeile (Objekt- oder Promptmodus) überspringen.
      IF lv_type = 'OBJECT_TYPE' OR lv_type = 'ITEM_TYPE'.
        CONTINUE.
      ENDIF.

      lv_key = |{ lv_type }:{ lv_name }|.
      INSERT lv_key INTO TABLE mt_done.
    ENDDO.

    CLOSE DATASET mv_result_file.
  ENDMETHOD.

  METHOD already_done.
    DATA(lv_key) = lcl_text=>item_key(
      iv_kind     = is_object-kind
      iv_object   = is_object-object
      iv_obj_name = is_object-obj_name ).

    READ TABLE mt_done TRANSPORTING NO FIELDS
      WITH TABLE KEY table_line = lv_key.

    rv_done = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD download.
    DATA:
      lt_lines TYPE STANDARD TABLE OF string,
      lv_line  TYPE string,
      lv_path  TYPE string,
      lv_file  TYPE string,
      lv_full  TYPE string,
      lv_act   TYPE i.

    IF sy-batch = abap_true.
      MESSAGE
        'Frontend-Download ist im Hintergrund nicht möglich.'
        TYPE 'S'.
      RETURN.
    ENDIF.

    OPEN DATASET iv_server_file FOR INPUT
      IN TEXT MODE ENCODING UTF-8.

    IF sy-subrc <> 0.
      MESSAGE |Datei { iv_server_file } nicht lesbar.|
        TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    DO.
      READ DATASET iv_server_file INTO lv_line.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      APPEND lv_line TO lt_lines.
    ENDDO.

    CLOSE DATASET iv_server_file.

    lv_file = iv_server_file.

    FIND REGEX '[^/]+$' IN lv_file
      MATCH OFFSET DATA(lv_off)
      MATCH LENGTH DATA(lv_length).

    IF sy-subrc = 0.
      lv_file = lv_file+lv_off(lv_length).
    ELSE.
      lv_file = 'ai_batch_result.tsv'.
    ENDIF.

    cl_gui_frontend_services=>file_save_dialog(
      EXPORTING
        default_file_name = lv_file
        default_extension = 'tsv'
        file_filter       = 'Excel TSV (*.tsv)|*.tsv|'
      CHANGING
        filename          = lv_file
        path              = lv_path
        fullpath          = lv_full
        user_action       = lv_act
      EXCEPTIONS
        OTHERS            = 1 ).

    IF sy-subrc <> 0 OR lv_act <> 0 OR lv_full IS INITIAL.
      RETURN.
    ENDIF.

    cl_gui_frontend_services=>gui_download(
      EXPORTING
        filename                = lv_full
        filetype                = 'ASC'
        codepage                = '4110'
        write_bom               = abap_true
      CHANGING
        data_tab                = lt_lines
      EXCEPTIONS
        no_batch                = 1
        gui_refuse_filetransfer = 2
        file_write_error        = 3
        no_authority            = 4
        OTHERS                  = 5 ).

    IF sy-subrc = 0.
      MESSAGE |Datei heruntergeladen: { lv_full }| TYPE 'S'.
    ELSE.
      MESSAGE |Download fehlgeschlagen, SY-SUBRC={ sy-subrc }.|
        TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_progress IMPLEMENTATION.
  METHOD constructor.
    mv_total = iv_total.
  ENDMETHOD.

  METHOD start.
    GET TIME STAMP FIELD mv_start_ts.
    info( |Massenverarbeitung startet mit { mv_total } Einträgen.| ).
  ENDMETHOD.

  METHOD info.
    " TYPE S schreibt im Hintergrund in das Job-Log.
    MESSAGE iv_text TYPE 'S'.

    " WRITE stellt die Information zusätzlich im Job-Spool bereit.
    WRITE: / iv_text.
  ENDMETHOD.

  METHOD object_started.
    DATA lv_suffix TYPE string.

    IF is_object-kind = gc_kind_object.
      lv_suffix = | Paket { is_object-devclass }|.
    ENDIF.

    info(
      |Start { iv_idx }/{ mv_total }: | &&
      |{ lcl_text=>item_label( is_object ) }{ lv_suffix }| ).
  ENDMETHOD.

  METHOD object_finished.
    DATA(lv_elapsed) =
      lcl_text=>duration_text( is_result-elapsed_s ).
    DATA(lv_eta) =
      lcl_text=>duration_text( is_result-eta_s ).

    info(
      |Fertig { is_result-idx }/{ is_result-total }: | &&
      |{ is_result-label }, | &&
      |Status { is_result-status }, | &&
      |Dauer { is_result-duration_s }s, | &&
      |Laufzeit { lv_elapsed }, ETA { lv_eta }| ).
  ENDMETHOD.

  METHOD get_elapsed.
    DATA lv_now TYPE timestampl.

    IF mv_start_ts IS INITIAL.
      RETURN.
    ENDIF.

    GET TIME STAMP FIELD lv_now.

    rv_seconds = cl_abap_tstmp=>subtract(
      tstmp1 = lv_now
      tstmp2 = mv_start_ts ).
  ENDMETHOD.

  METHOD get_eta.
    DATA(lv_elapsed) = get_elapsed( ).

    IF iv_finished <= 0 OR mv_total <= iv_finished.
      rv_seconds = 0.
      RETURN.
    ENDIF.

    rv_seconds =
      ( lv_elapsed * ( mv_total - iv_finished ) ) DIV iv_finished.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_batch_runner IMPLEMENTATION.
  METHOD run.
    DATA lt_objects TYPE tt_object.

    mv_run_id = build_run_id( ).

    mv_system_prompt = lcl_text=>build_prompt(
      it_range   = s_sysp[]
      iv_file    = CONV string( p_sysfil )
      iv_default = default_system_prompt( ) ).

    mv_user_prompt = lcl_text=>build_prompt(
      it_range   = s_usrp[]
      iv_file    = CONV string( p_usrfil )
      iv_default = CONV string( p_usrone ) ).

    build_paths( ).

    IF p_mprm = abap_true.
      lt_objects = NEW lcl_prompt_resolver( )->get_items( ).

      IF lt_objects IS INITIAL.
        MESSAGE 'Keine Prompts gefunden.'
          TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
    ELSE.
      lt_objects = NEW lcl_object_resolver( )->get_objects( ).

      IF lt_objects IS INITIAL.
        MESSAGE 'Keine Entwicklungsobjekte gefunden.'
          TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
    ENDIF.

    CREATE OBJECT mo_writer
      EXPORTING
        iv_result_file = gv_result_file
        iv_log_file    = gv_log_file.

    mo_writer->initialize(
      iv_header = build_header( )
      iv_resume = p_resume ).

    CREATE OBJECT mo_progress
      EXPORTING
        iv_total = lines( lt_objects ).

    build_services( ).

    DATA(lv_mode) = COND string(
      WHEN p_mprm = abap_true THEN 'Promptliste'
      ELSE 'Entwicklungsobjekte' ).

    mo_writer->write_log(
      |RUN { mv_run_id }; Modus { lv_mode }; Modell { p_model }; | &&
      |Einträge { lines( lt_objects ) }; Tools { mv_tools }| ).

    mo_progress->start( ).

    DATA:
      lv_total    TYPE i,
      lv_finished TYPE i.

    lv_total = lines( lt_objects ).

    LOOP AT lt_objects INTO DATA(ls_object).
      DATA(lv_idx) = sy-tabix.

      IF p_resume = abap_true AND
         mo_writer->already_done( ls_object ) = abap_true.

        lv_finished = lv_finished + 1.

        IF p_logfrq > 0 AND lv_finished MOD p_logfrq = 0.
          mo_progress->info(
            |Übersprungen { lv_idx }/{ lv_total }: | &&
            |{ lcl_text=>item_label( ls_object ) } | &&
            |bereits in Ergebnisdatei.| ).
        ENDIF.

        CONTINUE.
      ENDIF.

      mo_progress->object_started(
        iv_idx    = lv_idx
        is_object = ls_object ).

      DATA(ls_result) = process_object(
        is_object = ls_object
        iv_idx    = lv_idx
        iv_total  = lv_total ).

      lv_finished = lv_finished + 1.
      ls_result-elapsed_s = mo_progress->get_elapsed( ).
      ls_result-eta_s     = mo_progress->get_eta( lv_finished ).

      APPEND ls_result TO gt_results.
      mo_writer->write_result( ls_result ).
      mo_writer->write_log(
        |{ lv_idx }/{ lv_total } | &&
        |{ ls_result-label } | &&
        |Status={ ls_result-status } | &&
        |HTTP={ ls_result-http_status } | &&
        |Versuche={ ls_result-attempts } | &&
        |Dauer={ ls_result-duration_s }s | &&
        |ETA={ ls_result-eta_s }s| ).

      IF p_logfrq <= 1 OR lv_finished MOD p_logfrq = 0.
        mo_progress->object_finished( ls_result ).
      ENDIF.

      COMMIT WORK AND WAIT.

      IF p_pause > 0 AND lv_idx < lv_total.
        WAIT UP TO p_pause SECONDS.
      ENDIF.
    ENDLOOP.

    DATA(lv_elapsed_text) =
      lcl_text=>duration_text( mo_progress->get_elapsed( ) ).

    mo_progress->info(
      |Massenverarbeitung beendet. Laufzeit { lv_elapsed_text }. | &&
      |Ergebnis: { gv_result_file }; Log: { gv_log_file }| ).

    mo_writer->write_log(
      |RUN beendet; Laufzeit { lv_elapsed_text }.| ).
  ENDMETHOD.

  METHOD default_system_prompt.
    DATA(lv_newline) = cl_abap_char_utilities=>newline.

    IF p_mprm = abap_true.
      rv_text =
        |Du bist ein autonomer SAP-Analyseagent.| &&
        lv_newline &&
        |Bearbeite genau die gestellte Aufgabe anhand realer Systemdaten.| &&
        lv_newline &&
        |Stelle keine Rückfragen. Erfinde keine Objekte, Felder oder Ergebnisse.| &&
        lv_newline &&
        |Verwende die verfügbaren READ-only-Werkzeuge.| &&
        lv_newline &&
        |Gib als finale Antwort genau eine TSV-Datenzeile ohne Überschrift, | &&
        |ohne Markdown und ohne Codeblock aus.|.
    ELSE.
      rv_text =
        |Du bist ein autonomer SAP-Repository-Analyseagent.| &&
        lv_newline &&
        |Analysiere genau das übergebene Entwicklungsobjekt anhand realer Systemdaten.| &&
        lv_newline &&
        |Stelle keine Rückfragen. Erfinde keine Objekte, Felder oder Ergebnisse.| &&
        lv_newline &&
        |Verwende die verfügbaren READ-only-Werkzeuge.| &&
        lv_newline &&
        |Gib als finale Antwort genau eine TSV-Datenzeile ohne Überschrift, | &&
        |ohne Markdown und ohne Codeblock aus.|.
    ENDIF.
  ENDMETHOD.

  METHOD build_run_id.
    rv_run_id =
      |{ sy-datum }_{ sy-uzeit }_{ sy-uname }|.

    REPLACE ALL OCCURRENCES OF ':' IN rv_run_id WITH ``.
    REPLACE ALL OCCURRENCES OF '-' IN rv_run_id WITH ``.
    REPLACE ALL OCCURRENCES OF '/' IN rv_run_id WITH ``.
  ENDMETHOD.

  METHOD build_paths.
    DATA:
      lv_dir  TYPE string,
      lv_file TYPE string.

    lv_dir  = CONV string( p_outdir ).
    lv_file = CONV string( p_file ).

    REPLACE ALL OCCURRENCES OF '&SYSID&'
      IN lv_dir WITH sy-sysid.

    IF lv_dir IS INITIAL.
      MESSAGE 'Ausgabeverzeichnis ist leer.' TYPE 'E'.
    ENDIF.

    IF lv_file IS INITIAL.
      lv_file = |AI_BATCH_{ mv_run_id }.tsv|.
    ENDIF.

    IF lv_file NP '*.tsv'.
      lv_file = lv_file && '.tsv'.
    ENDIF.

    IF lv_dir CP '*/'.
      gv_result_file = lv_dir && lv_file.
    ELSE.
      gv_result_file = lv_dir && '/' && lv_file.
    ENDIF.

    gv_log_file = gv_result_file.
    REPLACE REGEX '\.tsv$' IN gv_log_file WITH '.log'.
  ENDMETHOD.

  METHOD build_header.
    " Technische Spalten je Modus, danach die vom Benutzer definierten
    " Ergebnisspalten. Spalte 1 und 2 sind der Fortsetzungsschlüssel.
    IF p_mprm = abap_true.
      rv_header =
        |ITEM_TYPE\tITEM_KEY\tPROMPT_NO\tTEMPLATE_VALUES\tPROMPT_TEXT\t|.
    ELSE.
      rv_header =
        |OBJECT_TYPE\tOBJECT_NAME\tPACKAGE\tAUTHOR\t|.
    ENDIF.

    rv_header = rv_header &&
      |RUN_STATUS\tCHAT_ID\tATTEMPTS\tSTEPS\tDURATION_S\tHTTP_STATUS\tERROR_TEXT\t| &&
      CONV string( p_header ).

    REPLACE ALL OCCURRENCES OF `\t`
      IN rv_header
      WITH cl_abap_char_utilities=>horizontal_tab.
  ENDMETHOD.

  METHOD build_services.
    CREATE OBJECT mo_repo.
    CREATE OBJECT mo_registry.

    mo_registry->discover( ).
    activate_tools( ).

    CREATE OBJECT mo_client
      EXPORTING
        iv_model      = CONV string( p_model )
        iv_api_key    = CONV string( p_key )
        iv_region     = CONV string( p_region )
        iv_reasoning  = CONV string( p_reason )
        iv_retry_max  = 1
        iv_retry_wait = 0.

    CREATE OBJECT mo_orch
      EXPORTING
        io_repo              = mo_repo
        io_registry          = mo_registry
        io_client            = mo_client
        iv_additional_prompt = mv_system_prompt
        iv_max_steps         = p_maxstp.
  ENDMETHOD.

  METHOD activate_tools.
    DATA:
      lt_ids   TYPE salv_t_row,
      lt_names TYPE string_table.

    mt_tools = mo_registry->get_all( ).

    LOOP AT mt_tools INTO DATA(ls_tool).
      IF tool_blacklisted( ls_tool-api_name ) = abap_true.
        CONTINUE.
      ENDIF.

      DATA(lv_allowed) = abap_false.

      IF s_tools[] IS INITIAL.
        lv_allowed = tool_allowed( ls_tool-api_name ).
      ELSE.
        LOOP AT s_tools INTO DATA(ls_selection).
          IF ls_tool-api_name CP CONV string( ls_selection-low ).
            lv_allowed = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF lv_allowed = abap_true.
        APPEND ls_tool-id       TO lt_ids.
        APPEND ls_tool-api_name TO lt_names.
      ENDIF.
    ENDLOOP.

    IF lt_ids IS INITIAL.
      MESSAGE 'Keine zulässigen KI-Werkzeuge ausgewählt.'
        TYPE 'E'.
    ENDIF.

    mo_registry->activate_ids( lt_ids ).

    mv_tools = concat_lines_of(
      table = lt_names
      sep   = ', ' ).
  ENDMETHOD.

  METHOD tool_allowed.
    rv_yes = abap_false.

    CASE iv_name.
      WHEN 'repo_info'
        OR 'source_read'
        OR 'source_grep'
        OR 'where_used'
        OR 'sql_select'
        OR 'artifact_read'
        OR 'artifact_grep'
        OR 'obj_versions'
        OR 'syntax_status'
        OR 'impact_analyze'
        OR 'ddic_field_map'
        OR 'select_breakdown'.
        rv_yes = abap_true.

      WHEN OTHERS.
        IF iv_name CP 'repo_info_*'
        OR iv_name CP 'source_read_*'
        OR iv_name CP 'source_grep_*'
        OR iv_name CP 'where_used_*'
        OR iv_name CP 'artifact_read_*'
        OR iv_name CP 'artifact_grep_*'.
          rv_yes = abap_true.
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD tool_blacklisted.
    rv_yes = abap_false.

    IF iv_name = 'abap_run'
    OR iv_name = 'code_compare'
    OR iv_name = 'make_download'
    OR iv_name = 'msg_i'
    OR iv_name CP 'abap_run_*'
    OR iv_name CP 'code_compare_*'
    OR iv_name CP 'make_download_*'
    OR iv_name CP 'msg_i_*'.

      rv_yes = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD build_user_text.
    DATA(lv_newline) = cl_abap_char_utilities=>newline.

    DATA(lv_format) =
      |Erwartete Ergebnisspalten: { p_header }| &&
      lv_newline &&
      |Liefere final genau eine Datenzeile mit | &&
      |{ p_cols } tabulatorgetrennten Spalten.| &&
      lv_newline &&
      |Keine Überschrift, kein Markdown, kein Codeblock, | &&
      |keine weitere Erklärung.|.

    " Promptlisten-Modus: Die Promptzeile ist der Benutzertext.
    IF is_object-kind = gc_kind_prompt.
      rv_text = is_object-prompt_text &&
        lv_newline &&
        lv_newline &&
        lv_format.
      RETURN.
    ENDIF.

    rv_text = mv_user_prompt.

    lcl_text=>replace_all(
      EXPORTING
        iv_old  = '&TYPE&'
        iv_new  = CONV string( is_object-object )
      CHANGING
        cv_text = rv_text ).

    lcl_text=>replace_all(
      EXPORTING
        iv_old  = '&NAME&'
        iv_new  = CONV string( is_object-obj_name )
      CHANGING
        cv_text = rv_text ).

    lcl_text=>replace_all(
      EXPORTING
        iv_old  = '&DEVC&'
        iv_new  = CONV string( is_object-devclass )
      CHANGING
        cv_text = rv_text ).

    lcl_text=>replace_all(
      EXPORTING
        iv_old  = '&AUTHOR&'
        iv_new  = CONV string( is_object-author )
      CHANGING
        cv_text = rv_text ).

    rv_text = rv_text &&
      lv_newline &&
      lv_newline &&
      |Zu analysierendes Objekt: | &&
      |{ is_object-object }:{ is_object-obj_name }| &&
      lv_newline &&
      |Paket: { is_object-devclass }| &&
      lv_newline &&
      |Autor: { is_object-author }| &&
      lv_newline &&
      lv_format.

    IF is_object-object = 'FUNC'.
      rv_text = rv_text &&
        lv_newline &&
        |Funktionsbaustein: { is_object-funcname }| &&
        lv_newline &&
        |Funktionsgruppe: { is_object-func_group }| &&
        lv_newline &&
        |Funktionsgruppenprogramm: { is_object-func_pool }| &&
        lv_newline &&
        |Funktionsinclude-Nummer: { is_object-func_include }| &&
        lv_newline &&
        |RFC-Modus: { is_object-fmode }| &&
        lv_newline &&
        |UPDATE-Modus: { is_object-utask }| &&
        lv_newline &&
        |Generiert: { is_object-generated }|.
    ENDIF.
  ENDMETHOD.

  METHOD process_object.
    DATA:
      lv_start_ts TYPE timestampl,
      lv_end_ts   TYPE timestampl,
      lv_continue TYPE abap_bool,
      lv_payload  TYPE string,
      lv_response TYPE string,
      lv_status   TYPE i,
      lv_error    TYPE string,
      lv_attempts TYPE i,
      lv_exists   TYPE abap_bool.

    GET TIME STAMP FIELD lv_start_ts.

    rs_result = VALUE #(
      idx         = iv_idx
      total       = iv_total
      kind        = is_object-kind
      object      = is_object-object
      obj_name    = is_object-obj_name
      devclass    = is_object-devclass
      author      = is_object-author
      prompt_no   = is_object-prompt_no
      prompt_key  = is_object-prompt_key
      prompt_text = is_object-prompt_text
      tpl_values  = is_object-tpl_values
      label       = lcl_text=>item_label( is_object )
      status      = gc_error ).

    " Existenzprüfung nur für Repositoryobjekte; Prompts werden immer gesendet.
    IF is_object-kind = gc_kind_object.
      IF is_object-object = 'FUNC'.
        SELECT SINGLE funcname
          FROM tfdir
          WHERE funcname = @is_object-funcname
          INTO @DATA(lv_function_exists).

        lv_exists = xsdbool( sy-subrc = 0 ).
      ELSE.
        SELECT SINGLE obj_name
          FROM tadir
          WHERE object   = @is_object-object
            AND obj_name = @is_object-obj_name
            AND delflag  = @space
          INTO @DATA(lv_repository_object).

        lv_exists = xsdbool( sy-subrc = 0 ).
      ENDIF.

      IF lv_exists = abap_false.
        rs_result-status = gc_skipped.

        IF is_object-object = 'FUNC'.
          rs_result-error_text =
            'Funktionsbaustein nicht in TFDIR gefunden.'.
        ELSE.
          rs_result-error_text =
            'Repositoryobjekt nicht in TADIR gefunden.'.
        ENDIF.

        RETURN.
      ENDIF.
    ENDIF.

    DATA(lv_title) = |{ mv_run_id } { rs_result-label }|.

    IF strlen( lv_title ) > 80.
      lv_title = lv_title(80).
    ENDIF.

    rs_result-session_id = mo_repo->create_session( lv_title ).

    mo_orch->begin_turn(
      iv_session_id = rs_result-session_id
      iv_user_text  = build_user_text( is_object ) ).

    DO p_maxstp TIMES.
      rs_result-steps = sy-index.

      lv_payload =
        mo_orch->build_next_payload( rs_result-session_id ).

      call_with_retry(
        EXPORTING
          iv_payload  = lv_payload
          iv_label    = rs_result-label
        IMPORTING
          ev_response = lv_response
          ev_status   = lv_status
          ev_error    = lv_error
          ev_attempts = lv_attempts ).

      rs_result-attempts =
        rs_result-attempts + lv_attempts.
      rs_result-http_status = lv_status.

      IF lv_error IS NOT INITIAL.
        rs_result-status     = gc_error.
        rs_result-error_text = lv_error.
        EXIT.
      ENDIF.

      mo_orch->handle_response(
        EXPORTING
          iv_session_id = rs_result-session_id
          iv_response   = lv_response
          iv_status     = lv_status
        IMPORTING
          ev_continue   = lv_continue ).

      IF lv_continue = abap_false.
        DATA lv_answer_status TYPE c LENGTH 12.

        read_last_answer(
          EXPORTING
            iv_session_id = rs_result-session_id
          IMPORTING
            ev_answer     = rs_result-answer
            ev_status     = lv_answer_status
            ev_http       = rs_result-http_status
            ev_error      = rs_result-error_text ).

        rs_result-status = lv_answer_status.

        IF rs_result-status = gc_ok.
          rs_result-output_row =
            lcl_text=>normalize_answer( rs_result-answer ).

          IF p_strict = abap_true AND
             lcl_text=>count_columns(
               rs_result-output_row ) <> p_cols.

            rs_result-status = gc_format.
            rs_result-error_text =
              |Erwartet: { p_cols } TSV-Spalten; erhalten: | &&
              |{ lcl_text=>count_columns(
                   rs_result-output_row ) }.|.
          ENDIF.
        ENDIF.

        EXIT.
      ENDIF.
    ENDDO.

    IF lv_continue = abap_true AND
       rs_result-status = gc_error.

      rs_result-status = gc_maxsteps.
      rs_result-error_text =
        |Maximale Schrittzahl { p_maxstp } erreicht.|.
    ENDIF.

    GET TIME STAMP FIELD lv_end_ts.

    rs_result-duration_s = cl_abap_tstmp=>subtract(
      tstmp1 = lv_end_ts
      tstmp2 = lv_start_ts ).
  ENDMETHOD.

  METHOD call_with_retry.
    DATA:
      lv_wait      TYPE i,
      lv_retryable TYPE abap_bool.

    CLEAR:
      ev_response,
      ev_status,
      ev_error,
      ev_attempts.

    DO.
      ev_attempts = ev_attempts + 1.

      CLEAR:
        ev_response,
        ev_status,
        ev_error.

      mo_client->post_raw(
        EXPORTING
          iv_payload  = iv_payload
        IMPORTING
          ev_response = ev_response
          ev_status   = ev_status
          ev_error    = ev_error ).

      lv_retryable = abap_false.

      IF ev_status = 0
      OR ev_status = 408
      OR ev_status = 425
      OR ev_status = 429
      OR ev_status = 500
      OR ev_status = 502
      OR ev_status = 503
      OR ev_status = 504
      OR ev_status = 529.

        lv_retryable = abap_true.
      ENDIF.

      IF lv_retryable = abap_false.
        RETURN.
      ENDIF.

      " p_retry = 0 bedeutet unbegrenzt.
      IF p_retry > 0 AND ev_attempts >= p_retry.
        IF ev_error IS INITIAL.
          ev_error =
            |Abbruch nach { ev_attempts } Versuchen, HTTP { ev_status }.|.
        ENDIF.
        RETURN.
      ENDIF.

      lv_wait = p_wait * ev_attempts.

      IF lv_wait > p_waitmx.
        lv_wait = p_waitmx.
      ENDIF.

      IF lv_wait < 1.
        lv_wait = 1.
      ENDIF.

      mo_progress->info(
        |{ iv_label }: temporärer Fehler HTTP { ev_status }; | &&
        |Versuch { ev_attempts }; nächster Versuch in { lv_wait }s; | &&
        |Retry-Limit { COND string(
          WHEN p_retry = 0 THEN 'unbegrenzt'
          ELSE CONV string( p_retry ) ) }.| ).

      mo_writer->write_log(
        |Retry { iv_label }; Versuch={ ev_attempts }; | &&
        |HTTP={ ev_status }; Wartezeit={ lv_wait }s; | &&
        |Fehler={ lcl_text=>clean_cell( ev_error ) }| ).

      WAIT UP TO lv_wait SECONDS.
    ENDDO.
  ENDMETHOD.

  METHOD read_last_answer.
    CLEAR:
      ev_answer,
      ev_status,
      ev_http,
      ev_error.

    ev_status = gc_error.

    SELECT *
      FROM zzwn00224895_aim
      WHERE session_id = @iv_session_id
      ORDER BY msg_seq DESCENDING
      INTO @DATA(ls_message)
      UP TO 1 ROWS.
    ENDSELECT.

    IF sy-subrc <> 0.
      ev_error = 'Keine Nachricht zur Session gefunden.'.
      RETURN.
    ENDIF.

    ev_answer = ls_message-content.
    ev_http   = ls_message-http_status.
    ev_error  = ls_message-error_text.

    IF ls_message-role = 'assistant'
    AND ls_message-msg_kind =
        zzwn00224895_ai_repo=>gc_kind_error.

      ev_status = gc_error.

      IF ev_error IS INITIAL.
        ev_error = ls_message-content.
      ENDIF.

      RETURN.
    ENDIF.

    IF ls_message-role = 'assistant'
    AND ls_message-msg_kind =
        zzwn00224895_ai_repo=>gc_kind_text
    AND ls_message-tool_calls IS INITIAL.

      ev_status = gc_ok.
      RETURN.
    ENDIF.

    ev_error =
      |Unerwartete letzte Nachricht: ROLE={ ls_message-role }, | &&
      |KIND={ ls_message-msg_kind }.|.
  ENDMETHOD.
ENDCLASS.

"----------------------------------------------------------------------
" Ereignisse
"----------------------------------------------------------------------
INITIALIZATION.
  gv_t00 = 'Verarbeitungsmodus'.
  gv_t01 = 'Entwicklungsobjekte'.
  gv_t07 = 'Promptliste und Template'.
  gv_t02 = 'KI und Werkzeuge'.
  gv_t03 = 'System- und Benutzerprompt'.
  gv_t04 = 'Tabellenformat'.
  gv_t05 = 'Laufzeit und Retry'.
  gv_t06 = 'Ausgabe'.

  gv_c01 = 'Entwicklungsobjekte analysieren (TADIR-Selektion)'.
  gv_c02 = 'Promptliste abarbeiten (eine Zeile = ein Prompt)'.
  gv_c03 = 'Template-Modus: %NAME% im Template wird zum Wertefeld'.
  gv_c04 = 'Prompts (1 Zeile = 1 Prompt)'.
  gv_c05 = 'Promptdatei Server (TXT/XLSX)'.
  gv_c06 = 'Template-Zeilen'.
  gv_c07 = 'Template-Datei Server'.

  gv_b01 = 'Systemprompt bearbeiten'.
  gv_b02 = 'Benutzerprompt bearbeiten'.
  gv_b03 = 'Ergebnis herunterladen'.
  gv_b04 = 'Promptliste bearbeiten'.
  gv_b05 = 'Promptliste importieren (TXT/CSV/XLSX)'.
  gv_b06 = 'Template bearbeiten'.

AT SELECTION-SCREEN OUTPUT.
  lcl_screen=>adjust( ).

AT SELECTION-SCREEN.
  CASE sscrfields-ucomm.
    WHEN gc_cmd_sysp.
      lcl_screen=>edit_range(
        EXPORTING iv_title = 'Systemprompt'
        CHANGING  ct_range = s_sysp[] ).

    WHEN gc_cmd_usrp.
      lcl_screen=>edit_range(
        EXPORTING iv_title = 'Benutzerprompt je Objekt'
        CHANGING  ct_range = s_usrp[] ).

    WHEN gc_cmd_prmp.
      lcl_screen=>edit_range(
        EXPORTING iv_title = 'Promptliste (eine Zeile = ein Prompt)'
        CHANGING  ct_range = s_prm[] ).

    WHEN gc_cmd_tplp.
      lcl_screen=>edit_range(
        EXPORTING iv_title = 'Prompt-Template (%NAME% = Platzhalter)'
        CHANGING  ct_range = s_tpl[] ).

    WHEN gc_cmd_prmi.
      lcl_screen=>import_prompt_list( ).

    WHEN gc_cmd_down.
      IF gv_result_file IS INITIAL.
        DATA(lv_dir) = CONV string( p_outdir ).
        REPLACE ALL OCCURRENCES OF '&SYSID&'
          IN lv_dir WITH sy-sysid.

        IF p_file IS NOT INITIAL.
          IF lv_dir CP '*/'.
            gv_result_file =
              lv_dir && CONV string( p_file ).
          ELSE.
            gv_result_file =
              lv_dir && '/' && CONV string( p_file ).
          ENDIF.
        ENDIF.
      ENDIF.

      NEW lcl_tsv_writer(
        iv_result_file = gv_result_file
        iv_log_file    = gv_log_file
        )->download( gv_result_file ).
  ENDCASE.

AT SELECTION-SCREEN ON p_cols.
  IF p_cols < 1.
    MESSAGE 'Die erwartete Spaltenzahl muss mindestens 1 sein.'
      TYPE 'E'.
  ENDIF.

AT SELECTION-SCREEN ON p_maxstp.
  IF p_maxstp < 1.
    MESSAGE 'Die maximale Schrittzahl muss mindestens 1 sein.'
      TYPE 'E'.
  ENDIF.

AT SELECTION-SCREEN ON p_retry.
  IF p_retry < 0.
    MESSAGE 'Retry muss 0 oder größer sein; 0 bedeutet unbegrenzt.'
      TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
  NEW lcl_batch_runner( )->run( ).
