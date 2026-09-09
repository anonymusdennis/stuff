CLASS zzwn00224895_ai_tool_texts DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  "===================================================================
  " AI tool: text maintenance with user review popup.
  "
  " Sub-tools (call codes):
  "   LIST     text_list           read the texts of a program text pool
  "                                or message class in one/all languages
  "   SUGGEST  text_suggest        propose ADD / CHANGE / DELETE / a
  "                                translation for exactly one text
  "   STATUS   text_review_status  see what the user decided and which
  "                                requests (retry / changes / deny) are
  "                                waiting for a new suggestion
  "
  " The tool never writes: every suggestion lands in the review popup
  " (ZZWN00224895_AI_TEXTS_REVIEW) where the user accepts and applies it.
  " Length limits are enforced here so the model gets an immediate,
  " actionable error instead of a truncated text.
  "===================================================================
  PUBLIC SECTION.
    INTERFACES zzwn00224895_ai_if_tool.

    CONSTANTS:
      gc_code_list    TYPE char20 VALUE 'LIST',
      gc_code_suggest TYPE char20 VALUE 'SUGGEST',
      gc_code_status  TYPE char20 VALUE 'STATUS'.

  PRIVATE SECTION.
    CONSTANTS gc_max_list_rows TYPE i VALUE 300.

    METHODS resolve_code
      IMPORTING iv_call_code   TYPE csequence
      RETURNING VALUE(rv_code) TYPE char20.

    METHODS param
      IMPORTING it_params       TYPE string_t
                iv_index        TYPE i
      RETURNING VALUE(rv_value) TYPE string.

    METHODS as_bool
      IMPORTING iv_value       TYPE string
                iv_default     TYPE abap_bool
      RETURNING VALUE(rv_bool) TYPE abap_bool.

    METHODS as_int
      IMPORTING iv_value      TYPE string
      RETURNING VALUE(rv_int) TYPE i.

    METHODS clean_text
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    METHODS do_list
      IMPORTING it_params TYPE string_t
      EXPORTING ev_ok     TYPE abap_bool
                ev_result TYPE string
                ev_error  TYPE string.

    METHODS do_suggest
      IMPORTING it_params TYPE string_t
      EXPORTING ev_ok     TYPE abap_bool
                ev_result TYPE string
                ev_error  TYPE string.

    METHODS do_status
      IMPORTING it_params TYPE string_t
      EXPORTING ev_ok     TYPE abap_bool
                ev_result TYPE string
                ev_error  TYPE string.

    METHODS normalize_action
      IMPORTING iv_action        TYPE string
      RETURNING VALUE(rv_action) TYPE char10.

    METHODS suggestion_line
      IMPORTING is_sug         TYPE zzwn00224895_ai_texts_api=>ty_suggestion
      RETURNING VALUE(rv_line) TYPE string.

    METHODS review_trailer
      RETURNING VALUE(rv_text) TYPE string.

    METHODS limits_text
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS zzwn00224895_ai_tool_texts IMPLEMENTATION.

  METHOD zzwn00224895_ai_if_tool~get_info.
    es_info-tool_key     = 'TEXTS'.
    es_info-display_name = 'Text maintenance (text pools, messages) with user review popup'.
    es_info-description  =
      `Propose a new, changed, deleted or translated text of a program text pool (text symbols, selection texts, ` &&
      `program title, list headings) or of a message class (T100). Nothing is written by this tool: each suggestion ` &&
      `appears in a review window where the user accepts and applies it, denies it with a reason or asks you for ` &&
      `another version. Read the current texts with text_list first, then send one text_suggest call per text and ` &&
      `language. Check text_review_status for user decisions and open requests. (For searching text pools ` &&
      `across many programs use the read-only text search tool instead; this tool changes texts.)`.
    es_info-api_name     = 'text_suggest'.
    es_info-category     = 'TEXTS'.
    es_info-writes       = abap_false.
    es_info-is_disabled  = abap_false.

    et_subtools = VALUE #(
      ( call_code   = gc_code_list
        sub_name    = 'text_list'
        description = `List the texts of a program text pool (PROG: text symbols I, selection texts S, title R, ` &&
                      `list headings H) or of a message class (MSAG) in one, several or all installed languages, ` &&
                      `including keys, current lengths and the maximum allowed length. Also loads the texts into the ` &&
                      `review window so the user can compare originals. Call this before suggesting.` )
      ( call_code   = gc_code_suggest
        sub_name    = 'text_suggest'
        description = `Register ONE suggestion for the user's review: ADD a missing text or translation, CHANGE an ` &&
                      `existing text, or DELETE an obsolete text, for one object / text id / key / language. ` &&
                      `The text must fit the maximum length (returned by text_list; error otherwise). For text ` &&
                      `symbols you may raise the defined length up to 132 with new_length. When the user asked for a ` &&
                      `retry or changes, answer with a new call and set replaces_id to the suggestion number given.` )
      ( call_code   = gc_code_status
        sub_name    = 'text_review_status'
        description = `Return the state of all suggestions in the review window (pending, accepted, applied, denied ` &&
                      `with reason, refused, superseded) plus the open user requests (retry / requested changes / ` &&
                      `denials with reason) that still need a new text_suggest from you. Use it after suggesting ` &&
                      `and whenever the user talks about the review.` ) ).
  ENDMETHOD.

  METHOD zzwn00224895_ai_if_tool~get_params.
    CASE resolve_code( iv_call_code ).
      WHEN gc_code_list.
        et_params = VALUE #(
          ( name = 'object_type'  dtype = 'string'  required = abap_true
            label = `PROG for a program/report text pool, MSAG for a message class` )
          ( name = 'object_name'  dtype = 'string'  required = abap_true
            label = `Program name (e.g. ZMY_REPORT) or message class (e.g. ZMY_MSG)` )
          ( name = 'languages'    dtype = 'string'  required = abap_false
            label = `Comma separated ISO language codes to show (e.g. "DE,EN"); empty = every language that has texts` )
          ( name = 'text_id'      dtype = 'string'  required = abap_false
            label = `Restrict PROG texts to one kind: I text symbols, S selection texts, R program title, H list headings` )
          ( name = 'key_pattern'  dtype = 'string'  required = abap_false
            label = `Restrict to keys matching this pattern, * as wildcard (e.g. "P_*" or "00*")` )
          ( name = 'open_review'  dtype = 'boolean' required = abap_false default_val = 'true'
            label = `Open / refresh the review window with these texts (default true)` ) ).

      WHEN gc_code_status.
        et_params = VALUE #(
          ( name = 'scope' dtype = 'string' required = abap_false default_val = 'OPEN'
            label = `OPEN = open user requests and undecided suggestions (default); ALL = every suggestion incl. applied/denied` ) ).

      WHEN OTHERS.
        et_params = VALUE #(
          ( name = 'object_type'  dtype = 'string'  required = abap_true
            label = `PROG for a program text pool, MSAG for a message class` )
          ( name = 'object_name'  dtype = 'string'  required = abap_true
            label = `Program name or message class` )
          ( name = 'text_id'      dtype = 'string'  required = abap_true
            label = `PROG: I text symbol, S selection text, R program title, H list heading; MSAG: M message` )
          ( name = 'text_key'     dtype = 'string'  required = abap_true
            label = `Text symbol number (001), selection text field name (P_MATNR), heading number, or message number (001); empty for R` )
          ( name = 'language'     dtype = 'string'  required = abap_true
            label = `ISO code of the language the new text is written in (DE, EN, FR ...)` )
          ( name = 'action'       dtype = 'string'  required = abap_true
            label = `ADD (new text or new translation), CHANGE (replace existing text), DELETE (remove the text in this language)` )
          ( name = 'new_text'     dtype = 'string'  required = abap_false
            label = `The proposed text (required for ADD/CHANGE); must not exceed the maximum length` )
          ( name = 'new_length'   dtype = 'integer' required = abap_false
            label = `Text symbols only: new defined length (>= text length, <= 132) when the current defined length is too short` )
          ( name = 'rationale'    dtype = 'string'  required = abap_false
            label = `One short sentence for the user why this text should change` )
          ( name = 'replaces_id'  dtype = 'integer' required = abap_false
            label = `Number of the suggestion this one replaces (after a retry / change request / denial)` ) ).
    ENDCASE.
  ENDMETHOD.

  METHOD zzwn00224895_ai_if_tool~execute.
    CLEAR: ev_result, ev_error.
    ev_ok = abap_false.
    TRY.
        CASE resolve_code( iv_call_code ).
          WHEN gc_code_list.
            do_list( EXPORTING it_params = it_params IMPORTING ev_ok = ev_ok ev_result = ev_result ev_error = ev_error ).
          WHEN gc_code_status.
            do_status( EXPORTING it_params = it_params IMPORTING ev_ok = ev_ok ev_result = ev_result ev_error = ev_error ).
          WHEN OTHERS.
            do_suggest( EXPORTING it_params = it_params IMPORTING ev_ok = ev_ok ev_result = ev_result ev_error = ev_error ).
        ENDCASE.
      CATCH cx_root INTO DATA(lx_error).
        ev_ok    = abap_false.
        ev_error = |Text tool failed: { lx_error->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.

  "------------------------------------------------------------------
  METHOD resolve_code.
    DATA(lv_code) = to_upper( condense( CONV string( iv_call_code ) ) ).
    IF lv_code CS 'LIST'.
      rv_code = gc_code_list.
    ELSEIF lv_code CS 'STATUS' OR lv_code CS 'REVIEW'.
      rv_code = gc_code_status.
    ELSE.
      rv_code = gc_code_suggest.
    ENDIF.
  ENDMETHOD.

  METHOD param.
    READ TABLE it_params INTO rv_value INDEX iv_index.
    IF sy-subrc <> 0.
      CLEAR rv_value.
    ENDIF.
  ENDMETHOD.

  METHOD as_bool.
    DATA(lv_val) = to_upper( condense( iv_value ) ).
    IF lv_val IS INITIAL.
      rv_bool = iv_default.
    ELSEIF lv_val = 'X' OR lv_val = 'TRUE' OR lv_val = '1' OR lv_val = 'YES' OR lv_val = 'Y' OR lv_val = 'JA'.
      rv_bool = abap_true.
    ELSE.
      rv_bool = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD as_int.
    DATA(lv_val) = condense( iv_value ).
    IF lv_val IS NOT INITIAL AND lv_val CO '0123456789'.
      rv_int = lv_val.
    ELSE.
      rv_int = 0.
    ENDIF.
  ENDMETHOD.

  METHOD clean_text.
    rv_text = iv_text.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_text WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_text WITH ` `.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_text WITH ` `.
    rv_text = condense( rv_text ).
  ENDMETHOD.

  METHOD normalize_action.
    CASE to_upper( condense( iv_action ) ).
      WHEN 'ADD' OR 'NEW' OR 'CREATE' OR 'INSERT' OR 'TRANSLATE' OR 'TRANSLATION'.
        rv_action = zzwn00224895_ai_texts_api=>gc_act_add.
      WHEN 'CHANGE' OR 'UPDATE' OR 'MODIFY' OR 'REPLACE' OR 'FIX' OR 'IMPROVE' OR 'EDIT'.
        rv_action = zzwn00224895_ai_texts_api=>gc_act_change.
      WHEN 'DELETE' OR 'REMOVE' OR 'DROP'.
        rv_action = zzwn00224895_ai_texts_api=>gc_act_delete.
      WHEN OTHERS.
        CLEAR rv_action.
    ENDCASE.
  ENDMETHOD.

  METHOD limits_text.
    rv_text = |Length limits: text symbol (I) <= its defined length, hard maximum { zzwn00224895_ai_texts_api=>gc_max_symbol } |
           && |(raise with new_length); selection text (S) <= { zzwn00224895_ai_texts_api=>gc_max_seltext }; |
           && |program title (R) <= { zzwn00224895_ai_texts_api=>gc_max_title }; list heading (H) <= { zzwn00224895_ai_texts_api=>gc_max_heading }; |
           && |message (M) <= { zzwn00224895_ai_texts_api=>gc_max_message }.|.
  ENDMETHOD.

  METHOD suggestion_line.
    rv_line = |#{ is_sug-id } [{ is_sug-status } { zzwn00224895_ai_texts_api=>status_label( is_sug-status ) }] |
           && |{ is_sug-obj_type } { is_sug-obj_name } { is_sug-text_id } { is_sug-text_key } { is_sug-iso } { is_sug-action }: |.
    IF is_sug-action = zzwn00224895_ai_texts_api=>gc_act_delete.
      rv_line = rv_line && |delete "{ is_sug-old_text }"|.
    ELSE.
      rv_line = rv_line && |"{ is_sug-new_text }"|.
      IF is_sug-old_text IS NOT INITIAL.
        rv_line = rv_line && | (was "{ is_sug-old_text }")|.
      ENDIF.
    ENDIF.
    IF is_sug-comment IS NOT INITIAL.
      rv_line = rv_line && | - user: "{ is_sug-comment }"|.
    ENDIF.
    IF is_sug-replaces_id > 0.
      rv_line = rv_line && | (replaces #{ is_sug-replaces_id })|.
    ENDIF.
    IF is_sug-replaced_by > 0.
      rv_line = rv_line && | (replaced by #{ is_sug-replaced_by })|.
    ENDIF.
    IF is_sug-request IS NOT INITIAL.
      rv_line = rv_line && | (request { is_sug-request })|.
    ENDIF.
    IF is_sug-error IS NOT INITIAL.
      rv_line = rv_line && | ERROR: { is_sug-error }|.
    ENDIF.
  ENDMETHOD.

  METHOD review_trailer.
    DATA(lo_review) = zzwn00224895_ai_texts_review=>get( ).
    rv_text = cl_abap_char_utilities=>newline && lo_review->summary_text( )
      && cl_abap_char_utilities=>newline && `Open user requests (answer each with text_suggest + replaces_id): `
      && cl_abap_char_utilities=>newline && lo_review->open_requests_text( ).
    DATA(lv_feedback) = lo_review->take_feedback( ).
    IF lv_feedback IS NOT INITIAL.
      rv_text = rv_text && cl_abap_char_utilities=>newline && `User feedback since your last call:`
        && cl_abap_char_utilities=>newline && lv_feedback.
    ENDIF.
  ENDMETHOD.

  "------------------------------------------------------------------
  METHOD do_list.
    DATA(lo_review) = zzwn00224895_ai_texts_review=>get( ).
    ev_ok = abap_false.

    DATA(lv_type)    = param( it_params = it_params iv_index = 1 ).
    DATA(lv_name)    = param( it_params = it_params iv_index = 2 ).
    DATA(lv_langs)   = param( it_params = it_params iv_index = 3 ).
    DATA(lv_text_id) = to_upper( condense( param( it_params = it_params iv_index = 4 ) ) ).
    DATA(lv_pattern) = to_upper( condense( param( it_params = it_params iv_index = 5 ) ) ).
    DATA(lv_open)    = as_bool( iv_value = param( it_params = it_params iv_index = 6 ) iv_default = abap_true ).

    lo_review->load_object(
      EXPORTING iv_obj_type = lv_type iv_obj_name = lv_name iv_force = abap_true
      IMPORTING es_object = DATA(ls_obj) ev_ok = DATA(lv_ok) ev_error = ev_error ).
    IF lv_ok = abap_false.
      RETURN.
    ENDIF.

    "--- language filter -------------------------------------------------
    DATA lt_langs TYPE STANDARD TABLE OF sy-langu WITH DEFAULT KEY.
    DATA lv_bad TYPE string.
    IF lv_langs IS NOT INITIAL.
      SPLIT lv_langs AT ',' INTO TABLE DATA(lt_raw).
      LOOP AT lt_raw INTO DATA(lv_raw).
        IF condense( lv_raw ) IS INITIAL.
          CONTINUE.
        ENDIF.
        zzwn00224895_ai_texts_api=>resolve_language(
          EXPORTING iv_lang = lv_raw
          IMPORTING ev_langu = DATA(lv_langu) ev_ok = DATA(lv_lok) ev_error = DATA(lv_lerr) ).
        IF lv_lok = abap_true.
          APPEND lv_langu TO lt_langs.
        ELSE.
          lv_bad = lv_bad && lv_lerr && ` `.
        ENDIF.
      ENDLOOP.
    ENDIF.

    DATA(lt_texts) = lo_review->get_originals( iv_obj_type = ls_obj-obj_type iv_obj_name = ls_obj-obj_name ).

    "Languages that actually have texts (respecting the filter).
    TYPES: BEGIN OF ty_lcount, langu TYPE sy-langu, iso TYPE laiso, count TYPE i, END OF ty_lcount.
    DATA lt_lcount TYPE STANDARD TABLE OF ty_lcount WITH DEFAULT KEY.
    LOOP AT lt_texts INTO DATA(ls_text).
      IF lt_langs IS NOT INITIAL.
        READ TABLE lt_langs TRANSPORTING NO FIELDS WITH KEY table_line = ls_text-langu.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
      ENDIF.
      READ TABLE lt_lcount ASSIGNING FIELD-SYMBOL(<ls_lc>) WITH KEY langu = ls_text-langu.
      IF sy-subrc <> 0.
        APPEND VALUE ty_lcount( langu = ls_text-langu iso = zzwn00224895_ai_texts_api=>iso_of( ls_text-langu ) ) TO lt_lcount ASSIGNING <ls_lc>.
      ENDIF.
      <ls_lc>-count = <ls_lc>-count + 1.
    ENDLOOP.
    SORT lt_lcount BY iso.
    "Master language first so the defined length column is meaningful.
    READ TABLE lt_lcount INTO DATA(ls_master_lc) WITH KEY langu = ls_obj-master_lang.
    IF sy-subrc = 0.
      DELETE lt_lcount INDEX sy-tabix.
      INSERT ls_master_lc INTO lt_lcount INDEX 1.
    ENDIF.

    "--- header -----------------------------------------------------------
    DATA(lv_nl) = cl_abap_char_utilities=>newline.
    ev_result = |{ ls_obj-obj_type } { ls_obj-obj_name } "{ ls_obj-description }" - master language |
             && |{ zzwn00224895_ai_texts_api=>iso_of( ls_obj-master_lang ) } - package { ls_obj-devclass }| && lv_nl.
    ev_result = ev_result && `Languages with texts: `.
    LOOP AT lt_lcount INTO DATA(ls_lc).
      ev_result = ev_result && |{ ls_lc-iso }({ ls_lc-count }) |.
    ENDLOOP.
    IF lt_lcount IS INITIAL.
      ev_result = ev_result && `none`.
    ENDIF.
    ev_result = ev_result && lv_nl && limits_text( ) && lv_nl.
    IF lv_bad IS NOT INITIAL.
      ev_result = ev_result && `Ignored languages: ` && lv_bad && lv_nl.
    ENDIF.

    "--- rows: one line per text key, all selected languages ----------------
    TYPES: BEGIN OF ty_key, text_id TYPE char1, text_key TYPE char8, END OF ty_key.
    DATA lt_keys TYPE SORTED TABLE OF ty_key WITH UNIQUE KEY text_id text_key.
    LOOP AT lt_texts INTO ls_text.
      IF lv_text_id IS NOT INITIAL AND ls_text-text_id <> lv_text_id.
        CONTINUE.
      ENDIF.
      IF lv_pattern IS NOT INITIAL.
        IF lv_pattern CA '*+'.
          IF NOT ls_text-text_key CP lv_pattern.
            CONTINUE.
          ENDIF.
        ELSEIF ls_text-text_key <> lv_pattern AND NOT ls_text-text_key CS lv_pattern.
          CONTINUE.
        ENDIF.
      ENDIF.
      INSERT VALUE ty_key( text_id = ls_text-text_id text_key = ls_text-text_key ) INTO TABLE lt_keys.
    ENDLOOP.

    DATA(lv_tab) = cl_abap_char_utilities=>horizontal_tab.
    ev_result = ev_result && |ID{ lv_tab }KEY{ lv_tab }DEFLEN/MAX{ lv_tab }TEXTS (ISO=text, - = missing)| && lv_nl.
    DATA lv_rows TYPE i.
    LOOP AT lt_keys INTO DATA(ls_key).
      lv_rows = lv_rows + 1.
      IF lv_rows > gc_max_list_rows.
        ev_result = ev_result && |... { lines( lt_keys ) - gc_max_list_rows } more rows. Narrow the list with text_id or key_pattern.| && lv_nl.
        EXIT.
      ENDIF.
      DATA(lv_max) = zzwn00224895_ai_texts_api=>max_length( iv_obj_type = ls_obj-obj_type iv_text_id = ls_key-text_id ).
      DATA(lv_def) = lv_max.
      IF ls_key-text_id = zzwn00224895_ai_texts_api=>gc_id_symbol AND ls_obj-obj_type = zzwn00224895_ai_texts_api=>gc_obj_prog.
        lo_review->find_original(
          EXPORTING iv_obj_type = ls_obj-obj_type iv_obj_name = ls_obj-obj_name
                    iv_text_id = ls_key-text_id iv_text_key = ls_key-text_key iv_langu = ls_obj-master_lang
          IMPORTING es_text = DATA(ls_master) ev_found = DATA(lv_found) ).
        IF lv_found = abap_true AND ls_master-length > 0.
          lv_def = ls_master-length.
        ENDIF.
      ENDIF.
      DATA(lv_line) = |{ ls_key-text_id }{ lv_tab }{ ls_key-text_key }{ lv_tab }{ lv_def }/{ lv_max }|.
      LOOP AT lt_lcount INTO ls_lc.
        lo_review->find_original(
          EXPORTING iv_obj_type = ls_obj-obj_type iv_obj_name = ls_obj-obj_name
                    iv_text_id = ls_key-text_id iv_text_key = ls_key-text_key iv_langu = ls_lc-langu
          IMPORTING es_text = ls_text ev_found = lv_found ).
        IF lv_found = abap_true.
          lv_line = lv_line && |{ lv_tab }{ ls_lc-iso }={ ls_text-text }|.
          IF ls_text-ddic_ref = abap_true.
            lv_line = lv_line && ` [DDIC]`.
          ENDIF.
        ELSE.
          lv_line = lv_line && |{ lv_tab }{ ls_lc-iso }=-|.
        ENDIF.
      ENDLOOP.
      ev_result = ev_result && lv_line && lv_nl.
    ENDLOOP.
    IF lt_keys IS INITIAL.
      ev_result = ev_result && `(no texts match)` && lv_nl.
    ENDIF.

    lo_review->note_ai_activity( |listed texts of { ls_obj-obj_type } { ls_obj-obj_name }| ).
    IF lv_open = abap_true AND zzwn00224895_ai_texts_review=>ui_available( ) = abap_true.
      lo_review->show( ).
      ev_result = ev_result && `Review window opened/refreshed with these texts.`.
    ENDIF.
    ev_result = ev_result && review_trailer( ).
    ev_ok = abap_true.
  ENDMETHOD.

  "------------------------------------------------------------------
  METHOD do_suggest.
    DATA(lo_review) = zzwn00224895_ai_texts_review=>get( ).
    ev_ok = abap_false.

    DATA(lv_type)     = param( it_params = it_params iv_index = 1 ).
    DATA(lv_name)     = param( it_params = it_params iv_index = 2 ).
    DATA(lv_text_id)  = to_upper( condense( param( it_params = it_params iv_index = 3 ) ) ).
    DATA(lv_key_in)   = param( it_params = it_params iv_index = 4 ).
    DATA(lv_lang_in)  = param( it_params = it_params iv_index = 5 ).
    DATA(lv_action)   = normalize_action( param( it_params = it_params iv_index = 6 ) ).
    DATA(lv_new_text) = clean_text( param( it_params = it_params iv_index = 7 ) ).
    DATA(lv_new_len)  = as_int( param( it_params = it_params iv_index = 8 ) ).
    DATA(lv_rational) = clean_text( param( it_params = it_params iv_index = 9 ) ).
    DATA(lv_replaces) = as_int( param( it_params = it_params iv_index = 10 ) ).

    "--- object -----------------------------------------------------------
    lo_review->load_object(
      EXPORTING iv_obj_type = lv_type iv_obj_name = lv_name
      IMPORTING es_object = DATA(ls_obj) ev_ok = DATA(lv_ok) ev_error = ev_error ).
    IF lv_ok = abap_false.
      RETURN.
    ENDIF.

    "--- text id / key ------------------------------------------------------
    IF ls_obj-obj_type = zzwn00224895_ai_texts_api=>gc_obj_msag.
      lv_text_id = zzwn00224895_ai_texts_api=>gc_id_message.
    ENDIF.
    IF strlen( lv_text_id ) <> 1 OR zzwn00224895_ai_texts_api=>valid_text_id(
         iv_obj_type = ls_obj-obj_type iv_text_id = CONV #( lv_text_id ) ) = abap_false.
      ev_error = COND #( WHEN ls_obj-obj_type = zzwn00224895_ai_texts_api=>gc_obj_prog
        THEN |Invalid text_id '{ lv_text_id }' for PROG. Use I (text symbol), S (selection text), R (program title), H (list heading) or T (list title).|
        ELSE |Invalid text_id '{ lv_text_id }' for MSAG. Use M.| ).
      RETURN.
    ENDIF.
    DATA lv_id TYPE char1.
    lv_id = lv_text_id.

    DATA(lv_key) = zzwn00224895_ai_texts_api=>normalize_key( iv_obj_type = ls_obj-obj_type iv_text_id = lv_id iv_key = lv_key_in ).
    IF lv_key IS INITIAL AND lv_id <> zzwn00224895_ai_texts_api=>gc_id_title.
      ev_error = 'text_key is required (text symbol number, selection text field name, heading number or message number).'.
      RETURN.
    ENDIF.
    IF ls_obj-obj_type = zzwn00224895_ai_texts_api=>gc_obj_msag AND NOT lv_key CO '0123456789'.
      ev_error = |Message number '{ lv_key_in }' must be numeric (001-999).|.
      RETURN.
    ENDIF.

    "--- language ---------------------------------------------------------
    zzwn00224895_ai_texts_api=>resolve_language(
      EXPORTING iv_lang = lv_lang_in
      IMPORTING ev_langu = DATA(lv_langu) ev_iso = DATA(lv_iso) ev_ok = lv_ok ev_error = ev_error ).
    IF lv_ok = abap_false.
      RETURN.
    ENDIF.

    "--- current text ------------------------------------------------------
    lo_review->find_original(
      EXPORTING iv_obj_type = ls_obj-obj_type iv_obj_name = ls_obj-obj_name
                iv_text_id = lv_id iv_text_key = lv_key iv_langu = lv_langu
      IMPORTING es_text = DATA(ls_cur) ev_found = DATA(lv_exists) ).
    lo_review->find_original(
      EXPORTING iv_obj_type = ls_obj-obj_type iv_obj_name = ls_obj-obj_name
                iv_text_id = lv_id iv_text_key = lv_key iv_langu = ls_obj-master_lang
      IMPORTING es_text = DATA(ls_master) ev_found = DATA(lv_master_exists) ).

    DATA(lv_kind) = zzwn00224895_ai_texts_api=>kind_label( iv_obj_type = ls_obj-obj_type iv_text_id = lv_id ).
    DATA(lv_what) = |{ ls_obj-obj_type } { ls_obj-obj_name } { lv_kind } { lv_key } ({ lv_iso })|.
    DATA lv_info TYPE string.

    "--- action -----------------------------------------------------------
    IF lv_action IS INITIAL.
      lv_action = COND #( WHEN lv_exists = abap_true THEN zzwn00224895_ai_texts_api=>gc_act_change
                          ELSE zzwn00224895_ai_texts_api=>gc_act_add ).
    ENDIF.
    IF lv_action = zzwn00224895_ai_texts_api=>gc_act_delete.
      IF lv_exists = abap_false.
        ev_error = |{ lv_what } has no text in { lv_iso }; nothing to delete.|.
        RETURN.
      ENDIF.
      CLEAR lv_new_text.
    ELSE.
      IF lv_new_text IS INITIAL.
        ev_error = |new_text is required for { lv_action }.|.
        RETURN.
      ENDIF.
      IF lv_exists = abap_true AND lv_action = zzwn00224895_ai_texts_api=>gc_act_add.
        lv_action = zzwn00224895_ai_texts_api=>gc_act_change.
        lv_info = |A text already exists in { lv_iso }; treated as CHANGE. |.
      ELSEIF lv_exists = abap_false AND lv_action = zzwn00224895_ai_texts_api=>gc_act_change.
        lv_action = zzwn00224895_ai_texts_api=>gc_act_add.
        lv_info = |No text exists in { lv_iso } yet; treated as ADD (translation). |.
      ENDIF.
      IF lv_exists = abap_true AND lv_new_text = ls_cur-text.
        ev_error = |The proposed text is identical to the current { lv_iso } text of { lv_what }. Nothing to suggest.|.
        RETURN.
      ENDIF.
      IF lv_exists = abap_false AND lv_master_exists = abap_false
         AND lv_langu <> ls_obj-master_lang AND ls_obj-obj_type = zzwn00224895_ai_texts_api=>gc_obj_prog.
        lv_info = lv_info && |Note: this text does not exist in the master language { zzwn00224895_ai_texts_api=>iso_of( ls_obj-master_lang ) } either. |.
      ENDIF.
    ENDIF.

    "--- length rules ---------------------------------------------------
    DATA(lv_max)   = zzwn00224895_ai_texts_api=>max_length( iv_obj_type = ls_obj-obj_type iv_text_id = lv_id ).
    DATA(lv_limit) = lv_max.
    DATA(lv_len)   = strlen( lv_new_text ).

    IF lv_action <> zzwn00224895_ai_texts_api=>gc_act_delete.
      IF lv_id = zzwn00224895_ai_texts_api=>gc_id_symbol AND ls_obj-obj_type = zzwn00224895_ai_texts_api=>gc_obj_prog.
        "Defined length: this language's row, else the master row, else free up to 132.
        IF lv_exists = abap_true AND ls_cur-length > 0.
          lv_limit = ls_cur-length.
        ELSEIF lv_master_exists = abap_true AND ls_master-length > 0.
          lv_limit = ls_master-length.
        ELSE.
          lv_limit = COND #( WHEN lv_len > 0 THEN lv_len ELSE lv_max ).
        ENDIF.
        IF lv_new_len > 0.
          IF lv_new_len > lv_max.
            ev_error = |new_length { lv_new_len } exceeds the hard maximum { lv_max } of a text symbol.|.
            RETURN.
          ENDIF.
          IF lv_new_len < lv_len.
            ev_error = |new_length { lv_new_len } is shorter than the text ({ lv_len } characters).|.
            RETURN.
          ENDIF.
          IF lv_new_len <> lv_limit.
            lv_info = lv_info && |Defined length changes { lv_limit } -> { lv_new_len }. |.
          ENDIF.
          lv_limit = lv_new_len.
        ENDIF.
        IF lv_len > lv_limit.
          ev_error = |Text has { lv_len } characters but the defined length of { lv_what } is { lv_limit } |
                  && |(hard maximum { lv_max }). Either shorten the text to { lv_limit } characters or repeat the call |
                  && |with new_length between { lv_len } and { lv_max } to extend the defined length.|.
          RETURN.
        ENDIF.
        lv_new_len = lv_limit.
      ELSE.
        IF lv_new_len > 0.
          lv_info = lv_info && |new_length is ignored for a { lv_kind } (fixed maximum { lv_max }). |.
        ENDIF.
        CLEAR lv_new_len.
        IF lv_len > lv_max.
          ev_error = |Text has { lv_len } characters; a { lv_kind } may have at most { lv_max }. |
                  && |Shorten it (no length extension is possible for this text kind).|.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.

    "--- register ---------------------------------------------------------
    DATA ls_new TYPE zzwn00224895_ai_texts_api=>ty_suggestion.
    ls_new-obj_type    = ls_obj-obj_type.
    ls_new-obj_name    = ls_obj-obj_name.
    ls_new-text_id     = lv_id.
    ls_new-text_key    = lv_key.
    ls_new-langu       = lv_langu.
    ls_new-iso         = lv_iso.
    ls_new-action      = lv_action.
    ls_new-old_text    = ls_cur-text.
    ls_new-old_length  = COND #( WHEN lv_exists = abap_true THEN ls_cur-length
                                 WHEN lv_master_exists = abap_true THEN ls_master-length ELSE 0 ).
    ls_new-new_text    = lv_new_text.
    ls_new-new_length  = lv_new_len.
    ls_new-max_len     = lv_max.
    ls_new-prefix      = ls_cur-prefix.
    ls_new-rationale   = lv_rational.
    ls_new-replaces_id = lv_replaces.

    lo_review->add_suggestion(
      EXPORTING is_new = ls_new
      IMPORTING ev_id = DATA(lv_sug_id) ev_ok = lv_ok ev_error = ev_error ev_info = DATA(lv_add_info) ).
    IF lv_ok = abap_false.
      RETURN.
    ENDIF.

    ev_result = |Suggestion #{ lv_sug_id } registered for review: { lv_what } { lv_action }|.
    IF lv_action = zzwn00224895_ai_texts_api=>gc_act_delete.
      ev_result = ev_result && | "{ ls_cur-text }".|.
    ELSE.
      ev_result = ev_result && | "{ lv_new_text }" ({ lv_len }/{ lv_limit }).|.
      IF lv_exists = abap_true.
        ev_result = ev_result && | Current: "{ ls_cur-text }".|.
      ENDIF.
    ENDIF.
    IF lv_info IS NOT INITIAL.
      ev_result = ev_result && ` ` && lv_info.
    ENDIF.
    IF lv_add_info IS NOT INITIAL.
      ev_result = ev_result && ` ` && lv_add_info.
    ENDIF.
    ev_result = ev_result && ` The user decides in the review window; nothing has been written.`.
    ev_result = ev_result && review_trailer( ).
    ev_ok = abap_true.
  ENDMETHOD.

  "------------------------------------------------------------------
  METHOD do_status.
    DATA(lo_review) = zzwn00224895_ai_texts_review=>get( ).
    CLEAR ev_error.
    DATA(lv_scope)  = to_upper( condense( param( it_params = it_params iv_index = 1 ) ) ).
    DATA(lv_nl)     = cl_abap_char_utilities=>newline.
    DATA(lv_all)    = xsdbool( lv_scope = 'ALL' OR lv_scope = 'FULL' OR lv_scope = 'EVERYTHING' ).

    DATA(lt_sug) = lo_review->get_suggestions( ).
    IF lt_sug IS INITIAL.
      ev_result = `No suggestions have been made yet.`.
    ELSE.
      ev_result = COND #( WHEN lv_all = abap_true THEN `All suggestions:` ELSE `Undecided suggestions and open requests (scope=ALL for everything):` ) && lv_nl.
      DATA lv_shown TYPE i.
      LOOP AT lt_sug INTO DATA(ls_sug).
        IF lv_all = abap_false
           AND ls_sug-request_open = abap_false
           AND ls_sug-status <> zzwn00224895_ai_texts_api=>gc_st_pending
           AND ls_sug-status <> zzwn00224895_ai_texts_api=>gc_st_accepted
           AND ls_sug-status <> zzwn00224895_ai_texts_api=>gc_st_failed.
          CONTINUE.
        ENDIF.
        ev_result = ev_result && suggestion_line( ls_sug ) && lv_nl.
        lv_shown = lv_shown + 1.
      ENDLOOP.
      IF lv_shown = 0.
        ev_result = ev_result && `(none)` && lv_nl.
      ENDIF.
    ENDIF.

    DATA(lt_obj) = lo_review->get_objects( ).
    IF lt_obj IS NOT INITIAL.
      ev_result = ev_result && `Objects loaded in the review: `.
      LOOP AT lt_obj INTO DATA(ls_obj).
        ev_result = ev_result && |{ ls_obj-obj_type } { ls_obj-obj_name } |.
      ENDLOOP.
      ev_result = ev_result && lv_nl.
    ENDIF.

    lo_review->note_ai_activity( 'checked the review status' ).
    ev_result = ev_result && review_trailer( ).
    ev_ok = abap_true.
  ENDMETHOD.

ENDCLASS.
