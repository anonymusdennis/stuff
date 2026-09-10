CLASS zzwn00224895_ai_texts_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  "===================================================================
  " Backend of the AI text maintenance tool.
  "
  " Reads and writes program text pools (text symbols, selection texts,
  " program title, list headings) and message class texts (T100) in any
  " installed language. Also owns the shared types of the review popup so
  " the other classes (HTML renderer, review controller, tool) only depend
  " on this one and can be activated in order API -> HTML -> REVIEW -> TOOL.
  "
  " Writes: lock the program (ESRDIRE), record the object on a transport
  " request when its package is transportable (TR_REQUEST_CHOICE +
  " TR_OBJECTS_INSERT, LIMU REPT / LIMU MESS), replace the text pool of
  " exactly one language (READ -> patch -> INSERT TEXTPOOL) and never
  " exceed the hard length limit of the text kind.
  "===================================================================
  PUBLIC SECTION.
    CONSTANTS:
      gc_obj_prog       TYPE char4 VALUE 'PROG',
      gc_obj_msag       TYPE char4 VALUE 'MSAG',
      gc_id_symbol      TYPE char1 VALUE 'I',
      gc_id_seltext     TYPE char1 VALUE 'S',
      gc_id_title       TYPE char1 VALUE 'R',
      gc_id_heading     TYPE char1 VALUE 'H',
      gc_id_listtitle   TYPE char1 VALUE 'T',
      gc_id_message     TYPE char1 VALUE 'M',
      gc_max_symbol     TYPE i VALUE 132,
      gc_max_seltext    TYPE i VALUE 30,
      gc_max_title      TYPE i VALUE 70,
      gc_max_heading    TYPE i VALUE 132,
      gc_max_message    TYPE i VALUE 73,
      "Selection texts carry 8 flag characters in front of the text
      "(position 1 = 'D' when the text is taken from the Dictionary).
      gc_seltext_prefix TYPE i VALUE 8.

    "--- suggestion status values (review popup) -----------------------
    CONSTANTS:
      gc_st_pending    TYPE char1 VALUE 'P',   "waiting for the user
      gc_st_accepted   TYPE char1 VALUE 'A',   "accepted, not yet written
      gc_st_applied    TYPE char1 VALUE 'X',   "written to the system
      gc_st_denied     TYPE char1 VALUE 'D',   "denied with a reason (AI informed)
      gc_st_refused    TYPE char1 VALUE 'R',   "refused silently (AI not informed)
      gc_st_retry      TYPE char1 VALUE 'T',   "user asked the AI for a new version
      gc_st_changes    TYPE char1 VALUE 'C',   "user asked for specific changes
      gc_st_superseded TYPE char1 VALUE 'S',   "replaced by a newer suggestion
      gc_st_failed     TYPE char1 VALUE 'F'.   "accepted but write failed

    CONSTANTS:
      gc_act_add    TYPE char10 VALUE 'ADD',
      gc_act_change TYPE char10 VALUE 'CHANGE',
      gc_act_delete TYPE char10 VALUE 'DELETE'.

    TYPES: BEGIN OF ty_text,
             obj_type TYPE char4,
             obj_name TYPE char40,
             text_id  TYPE char1,
             text_key TYPE char8,
             langu    TYPE sy-langu,
             text     TYPE string,
             length   TYPE i,        "defined length (text symbols) / actual length
             max_len  TYPE i,        "hard maximum of this text kind
             prefix   TYPE char8,    "raw flag prefix of selection texts
             ddic_ref TYPE abap_bool,
           END OF ty_text.
    TYPES tt_text TYPE STANDARD TABLE OF ty_text WITH DEFAULT KEY.
    TYPES tt_text_sorted TYPE SORTED TABLE OF ty_text
      WITH UNIQUE KEY obj_type obj_name text_id text_key langu.

    TYPES: BEGIN OF ty_lang,
             langu TYPE sy-langu,
             iso   TYPE laiso,
             name  TYPE string,
           END OF ty_lang.
    TYPES tt_lang TYPE STANDARD TABLE OF ty_lang WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_object,
             obj_type    TYPE char4,
             obj_name    TYPE char40,
             exists      TYPE abap_bool,
             master_lang TYPE sy-langu,
             devclass    TYPE devclass,
             description TYPE string,
           END OF ty_object.
    TYPES tt_object TYPE STANDARD TABLE OF ty_object WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_change,
             text_id  TYPE char1,
             text_key TYPE char8,
             delete   TYPE abap_bool,
             text     TYPE string,
             length   TYPE i,
             prefix   TYPE char8,
           END OF ty_change.
    TYPES tt_change TYPE STANDARD TABLE OF ty_change WITH DEFAULT KEY.

    "--- one AI suggestion as shown in the review popup ----------------
    TYPES: BEGIN OF ty_suggestion,
             id           TYPE i,
             obj_type     TYPE char4,
             obj_name     TYPE char40,
             text_id      TYPE char1,
             text_key     TYPE char8,
             langu        TYPE sy-langu,
             iso          TYPE laiso,
             action       TYPE char10,     "ADD / CHANGE / DELETE
             old_text     TYPE string,
             old_length   TYPE i,
             new_text     TYPE string,
             new_length   TYPE i,
             max_len      TYPE i,
             prefix       TYPE char8,
             rationale    TYPE string,
             status       TYPE char1,
             comment      TYPE string,     "user reason / change request
             replaces_id  TYPE i,
             replaced_by  TYPE i,
             request_open TYPE abap_bool,  "user request not yet answered by the AI
             request_kind TYPE char10,     "RETRY / CHANGE / DENY
             created_at   TYPE timestampl,
             decided_at   TYPE timestampl,
             request      TYPE trkorr,
             error        TYPE string,
           END OF ty_suggestion.
    TYPES tt_suggestion TYPE STANDARD TABLE OF ty_suggestion WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_view_lang,
             langu   TYPE sy-langu,
             iso     TYPE laiso,
             name    TYPE string,
             visible TYPE abap_bool,
             count   TYPE i,
           END OF ty_view_lang.
    TYPES tt_view_lang TYPE STANDARD TABLE OF ty_view_lang WITH DEFAULT KEY.

    "--- everything the HTML renderer needs -----------------------------
    TYPES: BEGIN OF ty_view,
             status_msg   TYPE string,
             status_kind  TYPE char1,      "E error / S success / I info
             ai_note      TYPE string,
             langs        TYPE tt_view_lang,
             objects      TYPE tt_object,
             originals    TYPE tt_text_sorted,
             suggestions  TYPE tt_suggestion,
             cnt_pending  TYPE i,
             cnt_accepted TYPE i,
             cnt_applied  TYPE i,
             cnt_waiting  TYPE i,
             cnt_denied   TYPE i,
           END OF ty_view.

    CLASS-METHODS installed_languages
      RETURNING VALUE(rt_langs) TYPE tt_lang.

    "Accepts SAP keys ('D'), ISO codes ('DE', 'de') and returns the SAP key.
    CLASS-METHODS resolve_language
      IMPORTING iv_lang  TYPE csequence
      EXPORTING ev_langu TYPE sy-langu
                ev_iso   TYPE laiso
                ev_ok    TYPE abap_bool
                ev_error TYPE string.

    CLASS-METHODS iso_of
      IMPORTING iv_langu      TYPE sy-langu
      RETURNING VALUE(rv_iso) TYPE laiso.

    CLASS-METHODS normalize_obj_type
      IMPORTING iv_type        TYPE csequence
      RETURNING VALUE(rv_type) TYPE char4.

    CLASS-METHODS object_info
      IMPORTING iv_obj_type      TYPE csequence
                iv_obj_name      TYPE csequence
      RETURNING VALUE(rs_object) TYPE ty_object.

    CLASS-METHODS valid_text_id
      IMPORTING iv_obj_type     TYPE char4
                iv_text_id      TYPE char1
      RETURNING VALUE(rv_valid) TYPE abap_bool.

    CLASS-METHODS max_length
      IMPORTING iv_obj_type   TYPE char4
                iv_text_id    TYPE char1
      RETURNING VALUE(rv_max) TYPE i.

    CLASS-METHODS kind_label
      IMPORTING iv_obj_type     TYPE char4
                iv_text_id      TYPE char1
      RETURNING VALUE(rv_label) TYPE string.

    CLASS-METHODS normalize_key
      IMPORTING iv_obj_type   TYPE char4
                iv_text_id    TYPE char1
                iv_key        TYPE csequence
      RETURNING VALUE(rv_key) TYPE char8.

    CLASS-METHODS read_texts
      IMPORTING iv_obj_type     TYPE char4
                iv_obj_name     TYPE csequence
                iv_langu        TYPE sy-langu
      RETURNING VALUE(rt_texts) TYPE tt_text.

    CLASS-METHODS read_all_languages
      IMPORTING iv_obj_type     TYPE char4
                iv_obj_name     TYPE csequence
      RETURNING VALUE(rt_texts) TYPE tt_text.

    CLASS-METHODS write_texts
      IMPORTING iv_obj_type TYPE char4
                iv_obj_name TYPE csequence
                iv_langu    TYPE sy-langu
                it_changes  TYPE tt_change
      EXPORTING ev_ok       TYPE abap_bool
                ev_error    TYPE string
                ev_request  TYPE trkorr.

    CLASS-METHODS status_label
      IMPORTING iv_status       TYPE char1
      RETURNING VALUE(rv_label) TYPE string.

  PRIVATE SECTION.
    TYPES tt_pool TYPE STANDARD TABLE OF textpool WITH DEFAULT KEY.

    CLASS-DATA gt_installed TYPE tt_lang.
    CLASS-DATA gt_all_langs TYPE tt_lang.
    CLASS-DATA gv_langs_loaded TYPE abap_bool.
    CLASS-DATA gv_last_request TYPE trkorr.

    CLASS-METHODS load_languages.

    CLASS-METHODS read_pool
      IMPORTING iv_obj_name     TYPE csequence
                iv_langu        TYPE sy-langu
      RETURNING VALUE(rt_texts) TYPE tt_text.

    CLASS-METHODS read_messages
      IMPORTING iv_obj_name     TYPE csequence
                iv_langu        TYPE sy-langu OPTIONAL
      RETURNING VALUE(rt_texts) TYPE tt_text.

    CLASS-METHODS write_pool
      IMPORTING iv_obj_name TYPE csequence
                iv_langu    TYPE sy-langu
                it_changes  TYPE tt_change
                is_object   TYPE ty_object
      EXPORTING ev_ok       TYPE abap_bool
                ev_error    TYPE string
                ev_request  TYPE trkorr.

    CLASS-METHODS write_messages
      IMPORTING iv_obj_name TYPE csequence
                iv_langu    TYPE sy-langu
                it_changes  TYPE tt_change
                is_object   TYPE ty_object
      EXPORTING ev_ok       TYPE abap_bool
                ev_error    TYPE string
                ev_request  TYPE trkorr.

    CLASS-METHODS record_transport
      IMPORTING iv_pgmid        TYPE pgmid DEFAULT 'LIMU'
                iv_object_class TYPE trobjtype
                iv_object       TYPE csequence
                iv_devclass     TYPE devclass
                iv_master_lang  TYPE sy-langu
      EXPORTING ev_ok           TYPE abap_bool
                ev_error        TYPE string
                ev_request      TYPE trkorr.

    "Opens the standard transport request popup (TR_REQUEST_CHOICE) when
    "the change is not local. The chosen request is reused for later writes.
    CLASS-METHODS choose_request
      IMPORTING iv_devclass      TYPE devclass
      EXPORTING ev_ok            TYPE abap_bool
                ev_error         TYPE string
                ev_request       TYPE trkorr.

    CLASS-METHODS pool_entry_text
      IMPORTING is_pool        TYPE textpool
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS message_text
      IMPORTING iv_subrc       TYPE sy-subrc
                iv_default     TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS zzwn00224895_ai_texts_api IMPLEMENTATION.

  METHOD load_languages.
    IF gv_langs_loaded = abap_true.
      RETURN.
    ENDIF.
    gv_langs_loaded = abap_true.

    SELECT spras, laiso FROM t002
      INTO TABLE @DATA(lt_t002).

    SELECT sprsl, sptxt FROM t002t
      WHERE spras = @sy-langu
      INTO TABLE @DATA(lt_t002t).

    SELECT spras FROM t002c
      WHERE lainst = @abap_true
      INTO TABLE @DATA(lt_inst).

    LOOP AT lt_t002 INTO DATA(ls_t002).
      DATA(ls_lang) = VALUE ty_lang( langu = ls_t002-spras iso = ls_t002-laiso ).
      READ TABLE lt_t002t INTO DATA(ls_t002t) WITH KEY sprsl = ls_t002-spras.
      IF sy-subrc = 0.
        ls_lang-name = ls_t002t-sptxt.
      ELSE.
        ls_lang-name = ls_t002-laiso.
      ENDIF.
      APPEND ls_lang TO gt_all_langs.
      READ TABLE lt_inst TRANSPORTING NO FIELDS WITH KEY spras = ls_t002-spras.
      IF sy-subrc = 0.
        APPEND ls_lang TO gt_installed.
      ENDIF.
    ENDLOOP.

    "Safety net: without T002C data at least the logon language is usable.
    IF gt_installed IS INITIAL.
      READ TABLE gt_all_langs INTO ls_lang WITH KEY langu = sy-langu.
      IF sy-subrc <> 0.
        ls_lang = VALUE #( langu = sy-langu iso = sy-langu name = sy-langu ).
      ENDIF.
      APPEND ls_lang TO gt_installed.
    ENDIF.
    SORT gt_installed BY iso.
  ENDMETHOD.

  METHOD installed_languages.
    load_languages( ).
    rt_langs = gt_installed.
  ENDMETHOD.

  METHOD resolve_language.
    load_languages( ).
    CLEAR: ev_langu, ev_iso, ev_error.
    ev_ok = abap_false.

    DATA(lv_in) = to_upper( condense( CONV string( iv_lang ) ) ).
    IF lv_in IS INITIAL.
      ev_error = 'Language is missing.'.
      RETURN.
    ENDIF.

    DATA ls_lang TYPE ty_lang.
    IF strlen( lv_in ) = 2.
      READ TABLE gt_all_langs INTO ls_lang WITH KEY iso = lv_in.
    ELSEIF strlen( lv_in ) = 1.
      READ TABLE gt_all_langs INTO ls_lang WITH KEY langu = lv_in(1).
      IF sy-subrc <> 0.
        "Lower-case internal keys exist (e.g. 'c'); try the raw value.
        DATA(lv_raw) = condense( CONV string( iv_lang ) ).
        READ TABLE gt_all_langs INTO ls_lang WITH KEY langu = lv_raw(1).
      ENDIF.
    ENDIF.

    IF ls_lang IS INITIAL.
      ev_error = |Unknown language '{ iv_lang }'. Use an ISO code such as DE or EN.|.
      RETURN.
    ENDIF.

    READ TABLE gt_installed TRANSPORTING NO FIELDS WITH KEY langu = ls_lang-langu.
    IF sy-subrc <> 0.
      DATA lv_list TYPE string.
      LOOP AT gt_installed INTO DATA(ls_inst).
        lv_list = COND #( WHEN lv_list IS INITIAL THEN CONV string( ls_inst-iso )
                          ELSE lv_list && `, ` && ls_inst-iso ).
      ENDLOOP.
      ev_error = |Language { ls_lang-iso } is not installed in this system. Installed: { lv_list }.|.
      RETURN.
    ENDIF.

    ev_langu = ls_lang-langu.
    ev_iso   = ls_lang-iso.
    ev_ok    = abap_true.
  ENDMETHOD.

  METHOD iso_of.
    load_languages( ).
    READ TABLE gt_all_langs INTO DATA(ls_lang) WITH KEY langu = iv_langu.
    IF sy-subrc = 0.
      rv_iso = ls_lang-iso.
    ELSE.
      rv_iso = iv_langu.
    ENDIF.
  ENDMETHOD.

  METHOD normalize_obj_type.
    DATA(lv_type) = to_upper( condense( CONV string( iv_type ) ) ).
    CASE lv_type.
      WHEN 'PROG' OR 'PROGRAM' OR 'REPORT' OR 'REPS' OR 'REPT' OR 'TEXTPOOL'.
        rv_type = gc_obj_prog.
      WHEN 'MSAG' OR 'MESSAGE' OR 'MESSAGES' OR 'MESSAGE_CLASS' OR 'MESS' OR 'T100'.
        rv_type = gc_obj_msag.
      WHEN OTHERS.
        CLEAR rv_type.
    ENDCASE.
  ENDMETHOD.

  METHOD object_info.
    rs_object-obj_type = normalize_obj_type( iv_obj_type ).
    rs_object-obj_name = to_upper( condense( CONV string( iv_obj_name ) ) ).
    IF rs_object-obj_type IS INITIAL OR rs_object-obj_name IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_tadir_obj TYPE trobjtype.
    CASE rs_object-obj_type.
      WHEN gc_obj_prog.
        DATA lv_prog TYPE syrepid.
        lv_prog = rs_object-obj_name.
        SELECT SINGLE name, rload FROM trdir
          WHERE name = @lv_prog
          INTO @DATA(ls_dir).
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.
        rs_object-exists      = abap_true.
        rs_object-master_lang = ls_dir-rload.
        lv_tadir_obj = 'PROG'.

        DATA lt_pool TYPE tt_pool.
        READ TEXTPOOL lv_prog INTO lt_pool LANGUAGE rs_object-master_lang.
        READ TABLE lt_pool INTO DATA(ls_pool) WITH KEY id = gc_id_title.
        IF sy-subrc = 0.
          rs_object-description = pool_entry_text( ls_pool ).
        ENDIF.

      WHEN gc_obj_msag.
        DATA lv_arbgb TYPE arbgb.
        lv_arbgb = rs_object-obj_name.
        SELECT SINGLE masterlang, stext FROM t100a
          WHERE arbgb = @lv_arbgb
          INTO @DATA(ls_t100a).
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.
        rs_object-exists      = abap_true.
        rs_object-master_lang = ls_t100a-masterlang.
        rs_object-description = ls_t100a-stext.
        lv_tadir_obj = 'MSAG'.
    ENDCASE.

    DATA lv_obj_name TYPE sobj_name.
    lv_obj_name = rs_object-obj_name.
    SELECT SINGLE devclass, masterlang FROM tadir
      WHERE pgmid = 'R3TR' AND object = @lv_tadir_obj AND obj_name = @lv_obj_name
      INTO @DATA(ls_tadir).
    IF sy-subrc = 0.
      rs_object-devclass = ls_tadir-devclass.
      IF rs_object-master_lang IS INITIAL.
        rs_object-master_lang = ls_tadir-masterlang.
      ENDIF.
    ENDIF.
    IF rs_object-master_lang IS INITIAL.
      rs_object-master_lang = sy-langu.
    ENDIF.
  ENDMETHOD.

  METHOD valid_text_id.
    CASE iv_obj_type.
      WHEN gc_obj_prog.
        rv_valid = xsdbool( iv_text_id = gc_id_symbol OR iv_text_id = gc_id_seltext OR
                            iv_text_id = gc_id_title  OR iv_text_id = gc_id_heading OR
                            iv_text_id = gc_id_listtitle ).
      WHEN gc_obj_msag.
        rv_valid = xsdbool( iv_text_id = gc_id_message ).
      WHEN OTHERS.
        rv_valid = abap_false.
    ENDCASE.
  ENDMETHOD.

  METHOD max_length.
    IF iv_obj_type = gc_obj_msag.
      rv_max = gc_max_message.
      RETURN.
    ENDIF.
    CASE iv_text_id.
      WHEN gc_id_symbol.    rv_max = gc_max_symbol.
      WHEN gc_id_seltext.   rv_max = gc_max_seltext.
      WHEN gc_id_title.     rv_max = gc_max_title.
      WHEN gc_id_heading.   rv_max = gc_max_heading.
      WHEN gc_id_listtitle. rv_max = gc_max_title.
      WHEN OTHERS.          rv_max = gc_max_symbol.
    ENDCASE.
  ENDMETHOD.

  METHOD kind_label.
    IF iv_obj_type = gc_obj_msag.
      rv_label = 'message'.
      RETURN.
    ENDIF.
    CASE iv_text_id.
      WHEN gc_id_symbol.    rv_label = 'text symbol'.
      WHEN gc_id_seltext.   rv_label = 'selection text'.
      WHEN gc_id_title.     rv_label = 'program title'.
      WHEN gc_id_heading.   rv_label = 'list heading'.
      WHEN gc_id_listtitle. rv_label = 'list title'.
      WHEN OTHERS.          rv_label = |text { iv_text_id }|.
    ENDCASE.
  ENDMETHOD.

  METHOD normalize_key.
    DATA(lv_key) = to_upper( condense( CONV string( iv_key ) ) ).
    IF iv_obj_type = gc_obj_msag.
      "Message numbers are three digits: '1' -> '001'.
      IF lv_key CO '0123456789' AND lv_key IS NOT INITIAL.
        DATA lv_num TYPE n LENGTH 3.
        lv_num = lv_key.
        lv_key = lv_num.
      ENDIF.
    ELSEIF iv_text_id = gc_id_symbol AND lv_key CO '0123456789' AND lv_key IS NOT INITIAL
       AND strlen( lv_key ) < 3.
      "Text symbol numbers are three characters: '1' -> '001'.
      DATA lv_sym TYPE n LENGTH 3.
      lv_sym = lv_key.
      lv_key = lv_sym.
    ELSEIF iv_text_id = gc_id_title.
      CLEAR lv_key.
    ENDIF.
    IF strlen( lv_key ) > 8.
      lv_key = lv_key(8).
    ENDIF.
    rv_key = lv_key.
  ENDMETHOD.

  METHOD pool_entry_text.
    IF is_pool-id = gc_id_seltext.
      rv_text = is_pool-entry+gc_seltext_prefix.
    ELSE.
      rv_text = is_pool-entry.
    ENDIF.
  ENDMETHOD.

  METHOD read_pool.
    DATA: lt_pool TYPE tt_pool,
          lv_prog TYPE syrepid.
    lv_prog = iv_obj_name.

    READ TEXTPOOL lv_prog INTO lt_pool LANGUAGE iv_langu.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_pool INTO DATA(ls_pool).
      DATA(ls_text) = VALUE ty_text(
        obj_type = gc_obj_prog
        obj_name = to_upper( iv_obj_name )
        text_id  = ls_pool-id
        text_key = ls_pool-key
        langu    = iv_langu
        max_len  = max_length( iv_obj_type = gc_obj_prog iv_text_id = ls_pool-id ) ).
      ls_text-text = pool_entry_text( ls_pool ).
      IF ls_pool-id = gc_id_seltext.
        ls_text-prefix   = ls_pool-entry(gc_seltext_prefix).
        ls_text-ddic_ref = xsdbool( ls_pool-entry(1) = 'D' ).
        ls_text-length   = strlen( ls_text-text ).
      ELSEIF ls_pool-id = gc_id_symbol.
        ls_text-length = ls_pool-length.
        IF ls_text-length < strlen( ls_text-text ).
          ls_text-length = strlen( ls_text-text ).
        ENDIF.
        IF ls_text-length > gc_max_symbol.
          ls_text-length = gc_max_symbol.
        ENDIF.
      ELSE.
        ls_text-length = strlen( ls_text-text ).
      ENDIF.
      APPEND ls_text TO rt_texts.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_messages.
    DATA lv_arbgb TYPE arbgb.
    lv_arbgb = iv_obj_name.

    IF iv_langu IS SUPPLIED AND iv_langu IS NOT INITIAL.
      SELECT sprsl, msgnr, text FROM t100
        WHERE arbgb = @lv_arbgb AND sprsl = @iv_langu
        ORDER BY msgnr
        INTO TABLE @DATA(lt_t100).
    ELSE.
      SELECT sprsl, msgnr, text FROM t100
        WHERE arbgb = @lv_arbgb
        ORDER BY msgnr, sprsl
        INTO TABLE @lt_t100.
    ENDIF.

    LOOP AT lt_t100 INTO DATA(ls_t100).
      APPEND VALUE ty_text(
        obj_type = gc_obj_msag
        obj_name = to_upper( iv_obj_name )
        text_id  = gc_id_message
        text_key = ls_t100-msgnr
        langu    = ls_t100-sprsl
        text     = ls_t100-text
        length   = strlen( ls_t100-text )
        max_len  = gc_max_message ) TO rt_texts.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_texts.
    CASE iv_obj_type.
      WHEN gc_obj_prog.
        rt_texts = read_pool( iv_obj_name = iv_obj_name iv_langu = iv_langu ).
      WHEN gc_obj_msag.
        rt_texts = read_messages( iv_obj_name = iv_obj_name iv_langu = iv_langu ).
    ENDCASE.
  ENDMETHOD.

  METHOD read_all_languages.
    CASE iv_obj_type.
      WHEN gc_obj_prog.
        DATA(lt_langs) = installed_languages( ).
        LOOP AT lt_langs INTO DATA(ls_lang).
          APPEND LINES OF read_pool( iv_obj_name = iv_obj_name iv_langu = ls_lang-langu ) TO rt_texts.
        ENDLOOP.
      WHEN gc_obj_msag.
        rt_texts = read_messages( iv_obj_name = iv_obj_name ).
    ENDCASE.
  ENDMETHOD.

  METHOD message_text.
    IF sy-msgid IS NOT INITIAL AND sy-msgty IS NOT INITIAL.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO rv_text.
    ENDIF.
    IF rv_text IS INITIAL.
      rv_text = |{ iv_default } (sy-subrc={ iv_subrc })|.
    ENDIF.
  ENDMETHOD.

  METHOD choose_request.
    ev_ok = abap_true.
    CLEAR: ev_error, ev_request.

    "Local objects ($-packages) and objects without a directory package
    "are not recorded.
    IF iv_devclass IS INITIAL OR iv_devclass(1) = '$'.
      RETURN.
    ENDIF.

    IF gv_last_request IS NOT INITIAL.
      ev_request = gv_last_request.
      RETURN.
    ENDIF.

    DATA: ls_req       TYPE trwbo_request_header,
          lv_request   TYPE e070-trkorr,
          lv_title     TYPE c LENGTH 60,
          lv_start_col TYPE sy-cucol VALUE 5,
          lv_start_row TYPE sy-curow VALUE 5.

    lv_title = 'AI text review: choose a workbench request'.

    "TR_REQUEST_CHOICE: export is ES_REQUEST (TRWBO_REQUEST_HEADER),
    "not EV_REQUEST. Object tables are optional IMPORTING, not TABLES.
    CALL FUNCTION 'TR_REQUEST_CHOICE'
      EXPORTING
        iv_request_types   = 'K'
        iv_title           = lv_title
        iv_start_column    = lv_start_col
        iv_start_row       = lv_start_row
        iv_with_error_log  = space
      IMPORTING
        es_request         = ls_req
      EXCEPTIONS
        invalid_request      = 1
        invalid_request_type = 2
        user_not_owner       = 3
        no_objects_appended  = 4
        enqueue_error        = 5
        cancelled_by_user    = 6
        recursive_call       = 7
        OTHERS               = 8.
    lv_request = ls_req-trkorr.
    CASE sy-subrc.
      WHEN 0.
        ev_request      = lv_request.
        gv_last_request = lv_request.
      WHEN 4.
        "Empty object list: some releases raise NO_OBJECTS_APPENDED even
        "when the user did pick a request. Keep the request if one came back.
        IF lv_request IS NOT INITIAL.
          ev_request      = lv_request.
          gv_last_request = lv_request.
        ELSE.
          ev_ok    = abap_false.
          ev_error = 'No transport request was selected; nothing written.'.
        ENDIF.
      WHEN 6.
        ev_ok    = abap_false.
        ev_error = 'Transport request selection was cancelled; nothing written.'.
      WHEN OTHERS.
        ev_ok    = abap_false.
        ev_error = message_text( iv_subrc = sy-subrc
                                 iv_default = 'Transport request selection failed' ).
    ENDCASE.

    IF ev_ok = abap_true AND ev_request IS INITIAL.
      ev_ok    = abap_false.
      ev_error = 'No transport request was selected; nothing written.'.
    ENDIF.
  ENDMETHOD.

  METHOD record_transport.
    ev_ok = abap_true.
    CLEAR: ev_error, ev_request.

    "Local objects ($-packages) and objects without directory entry are
    "not recorded.
    IF iv_devclass IS INITIAL OR iv_devclass(1) = '$'.
      RETURN.
    ENDIF.

    choose_request(
      EXPORTING iv_devclass = iv_devclass
      IMPORTING ev_ok       = ev_ok
                ev_error    = ev_error
                ev_request  = ev_request ).
    IF ev_ok = abap_false.
      RETURN.
    ENDIF.

    "CTS object list (E071 / KO200): LIMU REPT = program texts,
    "LIMU MESS = one T100 message, R3TR MSAG = whole message class.
    "RS_CORR_INSERT with workbench class REPT/MESS is rejected with
    "'Syntax fuer den Objektnamen ist nicht moeglich' (TK313).
    DATA: lt_ko200    TYPE STANDARD TABLE OF ko200,
          ls_ko200    TYPE ko200,
          lt_e071k    TYPE STANDARD TABLE OF e071k,
          lv_order    TYPE e070-trkorr,
          lv_task     TYPE e070-trkorr,
          lv_pgmid    TYPE e071-pgmid,
          lv_object   TYPE e071-object,
          lv_obj_name TYPE e071-obj_name.

    lv_pgmid    = iv_pgmid.
    IF lv_pgmid IS INITIAL.
      lv_pgmid = 'LIMU'.
    ENDIF.
    lv_object   = iv_object_class.
    lv_obj_name = iv_object.
    lv_order    = ev_request.
    IF lv_order IS INITIAL.
      lv_order = gv_last_request.
    ENDIF.

    CLEAR ls_ko200.
    ls_ko200-pgmid      = lv_pgmid.
    ls_ko200-object     = lv_object.
    ls_ko200-obj_name   = lv_obj_name.
    ls_ko200-objfunc    = 'K'.
    ls_ko200-devclass   = iv_devclass.
    ls_ko200-masterlang = iv_master_lang.
    ls_ko200-author     = sy-uname.
    APPEND ls_ko200 TO lt_ko200.

    CALL FUNCTION 'TR_OBJECTS_INSERT'
      EXPORTING
        wi_order = lv_order
      IMPORTING
        we_order = lv_order
        we_task  = lv_task
      TABLES
        wt_ko200 = lt_ko200
        wt_e071k = lt_e071k
      EXCEPTIONS
        cancel_edit_other_error = 1
        show_only_other_error   = 2
        OTHERS                  = 3.
    CASE sy-subrc.
      WHEN 0.
        IF lv_task IS NOT INITIAL.
          ev_request      = lv_task.
        ELSEIF lv_order IS NOT INITIAL.
          ev_request      = lv_order.
        ENDIF.
        IF ev_request IS NOT INITIAL.
          gv_last_request = ev_request.
        ENDIF.
      WHEN 1.
        ev_ok    = abap_false.
        ev_error = 'Transport request selection was cancelled; nothing written.'.
      WHEN OTHERS.
        "Object already on the request / locked by this user: still ok.
        IF sy-msgid = 'TK' AND ( sy-msgno = '133' OR sy-msgno = '168' OR sy-msgno = '320' ).
          ev_request = COND #( WHEN lv_order IS NOT INITIAL THEN lv_order ELSE gv_last_request ).
          ev_ok      = abap_true.
        ELSE.
          ev_ok    = abap_false.
          ev_error = message_text( iv_subrc = sy-subrc
                                   iv_default = |Could not add { lv_pgmid } { lv_object } { lv_obj_name } to a transport request| ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD write_texts.
    ev_ok = abap_false.
    CLEAR: ev_error, ev_request.

    IF it_changes IS INITIAL.
      ev_ok = abap_true.
      RETURN.
    ENDIF.

    DATA(ls_object) = object_info( iv_obj_type = iv_obj_type iv_obj_name = iv_obj_name ).
    IF ls_object-exists = abap_false.
      ev_error = |{ iv_obj_type } { to_upper( iv_obj_name ) } does not exist.|.
      RETURN.
    ENDIF.

    TRY.
        CASE ls_object-obj_type.
          WHEN gc_obj_prog.
            write_pool(
              EXPORTING iv_obj_name = ls_object-obj_name
                        iv_langu    = iv_langu
                        it_changes  = it_changes
                        is_object   = ls_object
              IMPORTING ev_ok       = ev_ok
                        ev_error    = ev_error
                        ev_request  = ev_request ).
          WHEN gc_obj_msag.
            write_messages(
              EXPORTING iv_obj_name = ls_object-obj_name
                        iv_langu    = iv_langu
                        it_changes  = it_changes
                        is_object   = ls_object
              IMPORTING ev_ok       = ev_ok
                        ev_error    = ev_error
                        ev_request  = ev_request ).
          WHEN OTHERS.
            ev_error = |Unsupported object type { iv_obj_type }.|.
        ENDCASE.
      CATCH cx_root INTO DATA(lx_error).
        ev_ok    = abap_false.
        "CX_SY_NO_HANDLER and similar wrappers carry the real cause in PREVIOUS.
        DATA(lx_cause) = lx_error.
        WHILE lx_cause->previous IS BOUND.
          lx_cause = lx_cause->previous.
        ENDWHILE.
        ev_error = |Write failed: { cl_abap_classdescr=>get_class_name( lx_cause ) }: { lx_cause->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.

  METHOD write_pool.
    DATA: lt_pool  TYPE tt_pool,
          ls_pool  TYPE textpool,
          lv_prog  TYPE syrepid,
          lv_lock  TYPE trdir-name,   "exact type of ENQUEUE_ESRDIRE-NAME
          lv_entry TYPE string.
    ev_ok = abap_false.
    lv_prog = iv_obj_name.
    lv_lock = lv_prog.

    CALL FUNCTION 'ENQUEUE_ESRDIRE'
      EXPORTING
        name           = lv_lock
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      ev_error = message_text( iv_subrc = sy-subrc iv_default = |Program { lv_prog } is locked| ).
      RETURN.
    ENDIF.

    record_transport(
      EXPORTING iv_object_class = 'REPT'
                iv_object       = lv_prog
                iv_devclass     = is_object-devclass
                iv_master_lang  = is_object-master_lang
      IMPORTING ev_ok           = DATA(lv_ok)
                ev_error        = ev_error
                ev_request      = ev_request ).
    IF lv_ok = abap_false.
      CALL FUNCTION 'DEQUEUE_ESRDIRE'
        EXPORTING
          name = lv_lock.
      RETURN.
    ENDIF.

    READ TEXTPOOL lv_prog INTO lt_pool LANGUAGE iv_langu.

    LOOP AT it_changes INTO DATA(ls_change).
      READ TABLE lt_pool ASSIGNING FIELD-SYMBOL(<ls_pool>)
        WITH KEY id = ls_change-text_id key = ls_change-text_key.
      DATA(lv_found) = xsdbool( sy-subrc = 0 ).
      DATA(lv_index) = sy-tabix.

      IF ls_change-delete = abap_true.
        IF lv_found = abap_true.
          DELETE lt_pool INDEX lv_index.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF lv_found = abap_false.
        CLEAR ls_pool.
        ls_pool-id  = ls_change-text_id.
        ls_pool-key = ls_change-text_key.
        APPEND ls_pool TO lt_pool ASSIGNING <ls_pool>.
      ENDIF.

      DATA(lv_max) = max_length( iv_obj_type = gc_obj_prog iv_text_id = ls_change-text_id ).
      lv_entry = ls_change-text.
      IF strlen( lv_entry ) > lv_max.
        lv_entry = lv_entry(lv_max).
      ENDIF.

      CASE ls_change-text_id.
        WHEN gc_id_seltext.
          DATA lv_prefix TYPE char8.
          lv_prefix = ls_change-prefix.
          IF lv_found = abap_true AND lv_prefix IS INITIAL.
            lv_prefix = <ls_pool>-entry(gc_seltext_prefix).
          ENDIF.
          "A Dictionary-referenced selection text gets an own text now.
          IF lv_prefix(1) = 'D' AND lv_entry IS NOT INITIAL.
            CLEAR lv_prefix.
          ENDIF.
          "RESPECTING BLANKS: the 8 flag characters are mostly spaces and
          "&& would drop them.
          CONCATENATE lv_prefix lv_entry INTO <ls_pool>-entry RESPECTING BLANKS.
          <ls_pool>-length = gc_seltext_prefix + strlen( lv_entry ).
        WHEN gc_id_symbol.
          <ls_pool>-entry = lv_entry.
          DATA(lv_len) = ls_change-length.
          IF lv_len <= 0 AND lv_found = abap_true.
            lv_len = <ls_pool>-length.
          ENDIF.
          IF lv_len < strlen( lv_entry ).
            lv_len = strlen( lv_entry ).
          ENDIF.
          IF lv_len > gc_max_symbol.
            lv_len = gc_max_symbol.
          ENDIF.
          <ls_pool>-length = lv_len.
        WHEN OTHERS.
          <ls_pool>-entry  = lv_entry.
          <ls_pool>-length = strlen( lv_entry ).
      ENDCASE.
    ENDLOOP.

    SORT lt_pool BY id key.

    IF lt_pool IS INITIAL.
      DELETE TEXTPOOL lv_prog LANGUAGE iv_langu.
    ELSE.
      INSERT TEXTPOOL lv_prog FROM lt_pool LANGUAGE iv_langu STATE 'A'.
    ENDIF.

    CALL FUNCTION 'DEQUEUE_ESRDIRE'
      EXPORTING
        name = lv_lock.

    ev_ok = abap_true.
  ENDMETHOD.

  METHOD write_messages.
    DATA: lv_arbgb  TYPE arbgb,
          lv_msgnr  TYPE msgnr,
          ls_t100   TYPE t100,
          ls_t100u  TYPE t100u,
          lv_object TYPE string.
    ev_ok = abap_false.
    lv_arbgb = iv_obj_name.

    LOOP AT it_changes INTO DATA(ls_change).
      lv_msgnr = ls_change-text_key.

      "LIMU MESS key = message class (20) + number (3); fall back to the
      "whole message class (R3TR MSAG) if the system rejects the class.
      lv_object = |{ lv_arbgb WIDTH = 20 }{ lv_msgnr }|.
      record_transport(
        EXPORTING iv_object_class = 'MESS'
                  iv_object       = lv_object
                  iv_devclass     = is_object-devclass
                  iv_master_lang  = is_object-master_lang
        IMPORTING ev_ok           = DATA(lv_ok)
                  ev_error        = ev_error
                  ev_request      = ev_request ).
      IF lv_ok = abap_false.
        record_transport(
          EXPORTING iv_pgmid        = 'R3TR'
                    iv_object_class = 'MSAG'
                    iv_object       = lv_arbgb
                    iv_devclass     = is_object-devclass
                    iv_master_lang  = is_object-master_lang
          IMPORTING ev_ok           = lv_ok
                    ev_error        = ev_error
                    ev_request      = ev_request ).
      ENDIF.
      IF lv_ok = abap_false.
        ROLLBACK WORK.
        RETURN.
      ENDIF.

      IF ls_change-delete = abap_true.
        DELETE FROM t100
          WHERE sprsl = @iv_langu AND arbgb = @lv_arbgb AND msgnr = @lv_msgnr.
        SELECT COUNT(*) FROM t100
          WHERE arbgb = @lv_arbgb AND msgnr = @lv_msgnr
          INTO @DATA(lv_remaining).
        IF lv_remaining = 0.
          DELETE FROM t100u WHERE arbgb = @lv_arbgb AND msgnr = @lv_msgnr.
        ENDIF.
        CONTINUE.
      ENDIF.

      CLEAR ls_t100.
      ls_t100-sprsl = iv_langu.
      ls_t100-arbgb = lv_arbgb.
      ls_t100-msgnr = lv_msgnr.
      ls_t100-text  = ls_change-text.
      MODIFY t100 FROM @ls_t100.
      IF sy-subrc <> 0.
        ROLLBACK WORK.
        ev_error = |Could not write message { lv_arbgb } { lv_msgnr } ({ iv_langu }).|.
        RETURN.
      ENDIF.

      SELECT SINGLE * FROM t100u
        WHERE arbgb = @lv_arbgb AND msgnr = @lv_msgnr
        INTO @ls_t100u.
      IF sy-subrc <> 0.
        CLEAR ls_t100u.
        ls_t100u-arbgb = lv_arbgb.
        ls_t100u-msgnr = lv_msgnr.
      ENDIF.
      ls_t100u-name  = sy-uname.
      ls_t100u-datum = sy-datum.
      MODIFY t100u FROM @ls_t100u.
    ENDLOOP.

    COMMIT WORK.
    ev_ok = abap_true.
  ENDMETHOD.

  METHOD status_label.
    CASE iv_status.
      WHEN gc_st_pending.    rv_label = 'pending review'.
      WHEN gc_st_accepted.   rv_label = 'accepted (not yet written)'.
      WHEN gc_st_applied.    rv_label = 'applied to the system'.
      WHEN gc_st_denied.     rv_label = 'denied with reason'.
      WHEN gc_st_refused.    rv_label = 'refused'.
      WHEN gc_st_retry.      rv_label = 'retry requested (waiting for AI)'.
      WHEN gc_st_changes.    rv_label = 'changes requested (waiting for AI)'.
      WHEN gc_st_superseded. rv_label = 'superseded'.
      WHEN gc_st_failed.     rv_label = 'apply failed'.
      WHEN OTHERS.           rv_label = |status { iv_status }|.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
