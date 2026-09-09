CLASS zzwn00224895_ai_texts_review DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  "===================================================================
  " Review model + popup controller of the AI text maintenance tool.
  "
  " One instance per internal session (singleton). The tool class feeds
  " it with suggestions while the assistant works; the user reviews them
  " in a modeless CL_GUI_DIALOGBOX_CONTAINER with an HTML viewer that sits
  " on top of the chat screen ("coop mode"): the chat's timer keeps
  " driving the model while the user accepts, applies, denies or asks for
  " new versions.
  "
  " Event flow (same rules as the chat report):
  "   * SAPEVENT / dialog close handlers only parse the request and run
  "     actions that need no frontend round trip (accept, refuse, retry,
  "     requests to the AI, language toggles). The page is repainted via
  "     queued control calls.
  "   * Actions that open dialogs (transport request popup on apply,
  "     confirmation on close) stay pending until the hosting report calls
  "     PROCESS_PENDING from its PAI module (see the CIMP extension).
  "
  " Feedback to the AI travels over two channels and is delivered once:
  "   * TAKE_FEEDBACK   - appended to the next result of any text_* tool
  "                       call while a turn is running.
  "   * TAKE_OUTBOX     - the hosting report submits it as a user message
  "                       when the assistant is idle (retry / change
  "                       request / deny with reason only).
  "===================================================================
  PUBLIC SECTION.
    CLASS-METHODS get
      RETURNING VALUE(ro_review) TYPE REF TO zzwn00224895_ai_texts_review.

    "abap_false in background jobs / RFC (no GUI): suggestions are still
    "recorded, but no popup is created.
    CLASS-METHODS ui_available
      RETURNING VALUE(rv_available) TYPE abap_bool.

    "--- model (used by the tool) -------------------------------------
    METHODS load_object
      IMPORTING iv_obj_type TYPE csequence
                iv_obj_name TYPE csequence
                iv_force    TYPE abap_bool DEFAULT abap_false
      EXPORTING es_object   TYPE zzwn00224895_ai_texts_api=>ty_object
                ev_ok       TYPE abap_bool
                ev_error    TYPE string.

    METHODS get_originals
      IMPORTING iv_obj_type     TYPE char4
                iv_obj_name     TYPE char40
      RETURNING VALUE(rt_texts) TYPE zzwn00224895_ai_texts_api=>tt_text.

    METHODS find_original
      IMPORTING iv_obj_type TYPE char4
                iv_obj_name TYPE char40
                iv_text_id  TYPE char1
                iv_text_key TYPE char8
                iv_langu    TYPE sy-langu
      EXPORTING es_text     TYPE zzwn00224895_ai_texts_api=>ty_text
                ev_found    TYPE abap_bool.

    "Validated and normalised suggestion; assigns id, links replacements,
    "opens/refreshes the popup.
    METHODS add_suggestion
      IMPORTING is_new   TYPE zzwn00224895_ai_texts_api=>ty_suggestion
      EXPORTING ev_id    TYPE i
                ev_ok    TYPE abap_bool
                ev_error TYPE string
                ev_info  TYPE string.

    METHODS get_suggestions
      RETURNING VALUE(rt_sug) TYPE zzwn00224895_ai_texts_api=>tt_suggestion.

    METHODS get_objects
      RETURNING VALUE(rt_objects) TYPE zzwn00224895_ai_texts_api=>tt_object.

    METHODS summary_text
      RETURNING VALUE(rv_text) TYPE string.

    METHODS open_requests_text
      RETURNING VALUE(rv_text) TYPE string.

    METHODS take_feedback
      RETURNING VALUE(rv_text) TYPE string.

    METHODS has_outbox
      RETURNING VALUE(rv_has) TYPE abap_bool.

    METHODS take_outbox
      RETURNING VALUE(rv_text) TYPE string.

    METHODS note_ai_activity
      IMPORTING iv_what TYPE string.

    "--- popup ----------------------------------------------------------
    METHODS is_open
      RETURNING VALUE(rv_open) TYPE abap_bool.

    METHODS show
      IMPORTING iv_anchor TYPE string OPTIONAL.

    METHODS refresh
      IMPORTING iv_anchor TYPE string OPTIONAL.

    METHODS close
      IMPORTING iv_discard TYPE abap_bool DEFAULT abap_false.

    "Hosting report: call from PAI (after cl_gui_cfw=>dispatch).
    METHODS process_pending.

    METHODS on_sapevent
      FOR EVENT sapevent OF cl_gui_html_viewer
      IMPORTING action getdata postdata.

    METHODS on_close
      FOR EVENT close OF cl_gui_dialogbox_container
      IMPORTING sender.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_feedback,
             id        TYPE i,
             kind      TYPE char10,
             text      TYPE string,
             prompt    TYPE abap_bool,   "may start a new turn when idle
             delivered TYPE abap_bool,
           END OF ty_feedback.
    TYPES tt_feedback TYPE STANDARD TABLE OF ty_feedback WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_pending,
             action  TYPE string,
             id      TYPE i,
             comment TYPE string,
             value   TYPE string,
           END OF ty_pending.

    TYPES: BEGIN OF ty_visible,
             langu   TYPE sy-langu,
             visible TYPE abap_bool,
           END OF ty_visible.
    TYPES tt_visible TYPE SORTED TABLE OF ty_visible WITH UNIQUE KEY langu.

    TYPES: BEGIN OF ty_group,
             obj_type TYPE char4,
             obj_name TYPE char40,
             langu    TYPE sy-langu,
             ids      TYPE STANDARD TABLE OF i WITH DEFAULT KEY,
             changes  TYPE zzwn00224895_ai_texts_api=>tt_change,
           END OF ty_group.
    TYPES tt_group TYPE SORTED TABLE OF ty_group WITH UNIQUE KEY obj_type obj_name langu.

    CONSTANTS:
      gc_caption     TYPE c LENGTH 20 VALUE 'AI text review',
      gc_width       TYPE i VALUE 1050,
      gc_height      TYPE i VALUE 680,
      gc_ok_code     TYPE sy-ucomm VALUE 'TXTREV',
      gc_max_comment TYPE i VALUE 600.

    CLASS-DATA go_instance TYPE REF TO zzwn00224895_ai_texts_review.

    DATA: mo_dialog      TYPE REF TO cl_gui_dialogbox_container,
          mo_html        TYPE REF TO cl_gui_html_viewer,
          mt_objects     TYPE zzwn00224895_ai_texts_api=>tt_object,
          mt_originals   TYPE zzwn00224895_ai_texts_api=>tt_text_sorted,
          mt_suggestions TYPE zzwn00224895_ai_texts_api=>tt_suggestion,
          mt_feedback    TYPE tt_feedback,
          mt_visible     TYPE tt_visible,
          mv_next_id     TYPE i VALUE 1,
          ms_pending     TYPE ty_pending,
          mv_has_pending TYPE abap_bool,
          mv_in_pending  TYPE abap_bool,
          mv_status      TYPE string,
          mv_status_kind TYPE char1,
          mv_ai_ts       TYPE timestampl,
          mv_ai_what     TYPE string,
          mv_user_closed TYPE abap_bool.

    METHODS ensure_popup
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    METHODS build_view
      RETURNING VALUE(rs_view) TYPE zzwn00224895_ai_texts_api=>ty_view.

    METHODS parse_event
      IMPORTING iv_action   TYPE c
                iv_getdata  TYPE c
                it_postdata TYPE cnht_post_data_tab.

    METHODS execute_pending
      IMPORTING iv_allow_dialog TYPE abap_bool.

    METHODS needs_dialog
      IMPORTING iv_action       TYPE string
      RETURNING VALUE(rv_needs) TYPE abap_bool.

    METHODS set_status
      IMPORTING iv_id      TYPE i
                iv_status  TYPE char1
                iv_comment TYPE string OPTIONAL.

    METHODS request_ai
      IMPORTING iv_id      TYPE i
                iv_kind    TYPE char10
                iv_comment TYPE string OPTIONAL.

    METHODS add_feedback
      IMPORTING iv_id     TYPE i
                iv_kind   TYPE char10
                iv_text   TYPE string
                iv_prompt TYPE abap_bool.

    METHODS apply_ids
      IMPORTING it_ids TYPE int4_table.

    METHODS apply_group
      CHANGING cs_group TYPE ty_group.

    METHODS confirm_close
      RETURNING VALUE(rv_close) TYPE abap_bool.

    METHODS discard_open.

    METHODS set_language_visible
      IMPORTING iv_langu   TYPE sy-langu
                iv_visible TYPE abap_bool.

    METHODS toggle_language
      IMPORTING iv_iso TYPE string.

    METHODS set_orig_mode
      IMPORTING iv_mode TYPE string.

    METHODS describe
      IMPORTING is_sug         TYPE zzwn00224895_ai_texts_api=>ty_suggestion
      RETURNING VALUE(rv_text) TYPE string.

    METHODS quote
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    METHODS form_value
      IMPORTING iv_payload      TYPE string
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS url_decode
      IMPORTING iv_in         TYPE string
      RETURNING VALUE(rv_out) TYPE string.

    METHODS now
      RETURNING VALUE(rv_ts) TYPE timestampl.

    METHODS set_banner
      IMPORTING iv_text TYPE string
                iv_kind TYPE char1.

    "Text of the innermost exception (CX_SY_NO_HANDLER and other wrappers
    "hide the real cause in PREVIOUS), prefixed with its class name.
    CLASS-METHODS root_cause
      IMPORTING ix_error       TYPE REF TO cx_root
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS zzwn00224895_ai_texts_review IMPLEMENTATION.

  METHOD get.
    IF go_instance IS NOT BOUND.
      CREATE OBJECT go_instance.
    ENDIF.
    ro_review = go_instance.
  ENDMETHOD.

  METHOD ui_available.
    rv_available = abap_false.
    IF sy-batch = abap_true.
      RETURN.
    ENDIF.
    IF cl_gui_alv_grid=>offline( ) <> 0.
      RETURN.
    ENDIF.
    rv_available = abap_true.
  ENDMETHOD.

  METHOD now.
    GET TIME STAMP FIELD rv_ts.
  ENDMETHOD.

  METHOD set_banner.
    mv_status      = iv_text.
    mv_status_kind = iv_kind.
  ENDMETHOD.

  METHOD root_cause.
    DATA(lx) = ix_error.
    DATA lv_depth TYPE i.
    WHILE lx IS BOUND AND lx->previous IS BOUND AND lv_depth < 10.
      lx = lx->previous.
      lv_depth = lv_depth + 1.
    ENDWHILE.
    IF lx IS NOT BOUND.
      RETURN.
    ENDIF.
    TRY.
        rv_text = |{ cl_abap_classdescr=>get_class_name( lx ) }: { lx->get_text( ) }|.
      CATCH cx_root.
        rv_text = lx->get_text( ).
    ENDTRY.
    IF lx <> ix_error.
      rv_text = |{ rv_text } [wrapped in { ix_error->get_text( ) }]|.
    ENDIF.
  ENDMETHOD.

  METHOD quote.
    rv_text = `"` && iv_text && `"`.
  ENDMETHOD.

  METHOD describe.
    rv_text = |{ is_sug-obj_type } { is_sug-obj_name } { zzwn00224895_ai_texts_api=>kind_label( iv_obj_type = is_sug-obj_type iv_text_id = is_sug-text_id ) }|.
    IF is_sug-text_key IS NOT INITIAL.
      rv_text = rv_text && | { is_sug-text_key }|.
    ENDIF.
    rv_text = rv_text && |, language { is_sug-iso }|.
  ENDMETHOD.

  "------------------------------------------------------------------
  " model
  "------------------------------------------------------------------
  METHOD load_object.
    CLEAR: es_object, ev_error.
    ev_ok = abap_false.

    es_object = zzwn00224895_ai_texts_api=>object_info( iv_obj_type = iv_obj_type iv_obj_name = iv_obj_name ).
    IF es_object-obj_type IS INITIAL.
      ev_error = |Unknown object type '{ iv_obj_type }'. Use PROG (program text pool) or MSAG (message class).|.
      RETURN.
    ENDIF.
    IF es_object-exists = abap_false.
      ev_error = |{ es_object-obj_type } { es_object-obj_name } does not exist in this system.|.
      RETURN.
    ENDIF.

    READ TABLE mt_objects TRANSPORTING NO FIELDS
      WITH KEY obj_type = es_object-obj_type obj_name = es_object-obj_name.
    IF sy-subrc = 0 AND iv_force = abap_false.
      ev_ok = abap_true.
      RETURN.
    ENDIF.

    IF sy-subrc = 0.
      DELETE mt_objects WHERE obj_type = es_object-obj_type AND obj_name = es_object-obj_name.
      DELETE mt_originals WHERE obj_type = es_object-obj_type AND obj_name = es_object-obj_name.
    ENDIF.
    APPEND es_object TO mt_objects.

    DATA(lt_texts) = zzwn00224895_ai_texts_api=>read_all_languages(
      iv_obj_type = es_object-obj_type iv_obj_name = es_object-obj_name ).
    LOOP AT lt_texts INTO DATA(ls_text).
      INSERT ls_text INTO TABLE mt_originals.
    ENDLOOP.

    "Default visibility: master language on; other languages keep their
    "previous choice, unknown ones start hidden.
    set_language_visible( iv_langu = es_object-master_lang iv_visible = abap_true ).
    LOOP AT lt_texts INTO ls_text.
      READ TABLE mt_visible TRANSPORTING NO FIELDS WITH TABLE KEY langu = ls_text-langu.
      IF sy-subrc <> 0.
        INSERT VALUE ty_visible( langu = ls_text-langu visible = abap_false ) INTO TABLE mt_visible.
      ENDIF.
    ENDLOOP.
    ev_ok = abap_true.
  ENDMETHOD.

  METHOD get_originals.
    LOOP AT mt_originals INTO DATA(ls_text) WHERE obj_type = iv_obj_type AND obj_name = iv_obj_name.
      APPEND ls_text TO rt_texts.
    ENDLOOP.
  ENDMETHOD.

  METHOD find_original.
    CLEAR es_text.
    READ TABLE mt_originals INTO es_text
      WITH TABLE KEY obj_type = iv_obj_type obj_name = iv_obj_name
                     text_id = iv_text_id text_key = iv_text_key langu = iv_langu.
    ev_found = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD set_language_visible.
    READ TABLE mt_visible ASSIGNING FIELD-SYMBOL(<ls_vis>) WITH TABLE KEY langu = iv_langu.
    IF sy-subrc = 0.
      <ls_vis>-visible = iv_visible.
    ELSE.
      INSERT VALUE ty_visible( langu = iv_langu visible = iv_visible ) INTO TABLE mt_visible.
    ENDIF.
  ENDMETHOD.

  METHOD add_suggestion.
    DATA ls_sug TYPE zzwn00224895_ai_texts_api=>ty_suggestion.
    CLEAR: ev_id, ev_error, ev_info.
    ev_ok = abap_false.
    ls_sug = is_new.

    "Identical open suggestion already there? Return it instead of a copy.
    LOOP AT mt_suggestions INTO DATA(ls_dup)
         WHERE obj_type = ls_sug-obj_type AND obj_name = ls_sug-obj_name
           AND text_id  = ls_sug-text_id  AND text_key = ls_sug-text_key
           AND langu    = ls_sug-langu    AND action   = ls_sug-action
           AND new_text = ls_sug-new_text
           AND ( status = zzwn00224895_ai_texts_api=>gc_st_pending
              OR status = zzwn00224895_ai_texts_api=>gc_st_accepted ).
      ev_id   = ls_dup-id.
      ev_ok   = abap_true.
      ev_info = |Identical suggestion #{ ls_dup-id } is already under review; no duplicate created.|.
      RETURN.
    ENDLOOP.

    ls_sug-id         = mv_next_id.
    mv_next_id        = mv_next_id + 1.
    ls_sug-status     = zzwn00224895_ai_texts_api=>gc_st_pending.
    ls_sug-created_at = now( ).
    CLEAR: ls_sug-request_open, ls_sug-request_kind, ls_sug-replaced_by, ls_sug-comment, ls_sug-error, ls_sug-request.

    "Link to the request it answers: explicit replaces_id, otherwise the
    "open request for the same text and language.
    IF ls_sug-replaces_id <= 0.
      LOOP AT mt_suggestions INTO DATA(ls_open)
           WHERE request_open = abap_true
             AND obj_type = ls_sug-obj_type AND obj_name = ls_sug-obj_name
             AND text_id  = ls_sug-text_id  AND text_key = ls_sug-text_key
             AND langu    = ls_sug-langu.
        ls_sug-replaces_id = ls_open-id.
        EXIT.
      ENDLOOP.
    ENDIF.
    IF ls_sug-replaces_id > 0.
      READ TABLE mt_suggestions ASSIGNING FIELD-SYMBOL(<ls_old>) WITH KEY id = ls_sug-replaces_id.
      IF sy-subrc = 0.
        <ls_old>-request_open = abap_false.
        IF <ls_old>-status <> zzwn00224895_ai_texts_api=>gc_st_applied.
          <ls_old>-status      = zzwn00224895_ai_texts_api=>gc_st_superseded.
          <ls_old>-replaced_by = ls_sug-id.
        ENDIF.
        ev_info = |Suggestion #{ ls_sug-replaces_id } is superseded by #{ ls_sug-id }.|.
      ELSE.
        CLEAR ls_sug-replaces_id.
      ENDIF.
    ENDIF.

    APPEND ls_sug TO mt_suggestions.
    set_language_visible( iv_langu = ls_sug-langu iv_visible = abap_true ).
    ev_id = ls_sug-id.
    ev_ok = abap_true.

    note_ai_activity( |added suggestion #{ ls_sug-id }| ).
    IF ui_available( ) = abap_true.
      show( |s{ ls_sug-id }| ).
    ENDIF.
  ENDMETHOD.

  METHOD get_suggestions.
    rt_sug = mt_suggestions.
  ENDMETHOD.

  METHOD get_objects.
    rt_objects = mt_objects.
  ENDMETHOD.

  METHOD summary_text.
    DATA: lv_p TYPE i, lv_a TYPE i, lv_x TYPE i, lv_w TYPE i, lv_d TYPE i, lv_r TYPE i.
    LOOP AT mt_suggestions INTO DATA(ls_sug).
      CASE ls_sug-status.
        WHEN zzwn00224895_ai_texts_api=>gc_st_pending.  lv_p = lv_p + 1.
        WHEN zzwn00224895_ai_texts_api=>gc_st_accepted. lv_a = lv_a + 1.
        WHEN zzwn00224895_ai_texts_api=>gc_st_applied.  lv_x = lv_x + 1.
        WHEN zzwn00224895_ai_texts_api=>gc_st_retry OR zzwn00224895_ai_texts_api=>gc_st_changes.
          lv_w = lv_w + 1.
        WHEN zzwn00224895_ai_texts_api=>gc_st_denied.   lv_d = lv_d + 1.
        WHEN zzwn00224895_ai_texts_api=>gc_st_refused.  lv_r = lv_r + 1.
      ENDCASE.
    ENDLOOP.
    rv_text = |Review: { lv_p } pending, { lv_a } accepted (not written), { lv_x } applied, |
           && |{ lv_w } waiting for your new version, { lv_d } denied, { lv_r } refused. |.
    IF ui_available( ) = abap_false.
      rv_text = rv_text && 'No GUI: suggestions are recorded only.'.
    ELSEIF is_open( ) = abap_true.
      rv_text = rv_text && 'Review window is open.'.
    ELSEIF mv_user_closed = abap_true.
      rv_text = rv_text && 'Review window was closed by the user.'.
    ELSE.
      rv_text = rv_text && 'Review window is not open.'.
    ENDIF.
  ENDMETHOD.

  METHOD open_requests_text.
    LOOP AT mt_suggestions INTO DATA(ls_sug) WHERE request_open = abap_true.
      DATA(lv_line) = |#{ ls_sug-id } { ls_sug-request_kind }: { describe( ls_sug ) }. |.
      IF ls_sug-comment IS NOT INITIAL.
        lv_line = lv_line && |User comment: { quote( ls_sug-comment ) }. |.
      ENDIF.
      IF ls_sug-action = zzwn00224895_ai_texts_api=>gc_act_delete.
        lv_line = lv_line && |Rejected proposal: delete { quote( ls_sug-old_text ) }. |.
      ELSE.
        lv_line = lv_line && |Rejected text: { quote( ls_sug-new_text ) }. |.
      ENDIF.
      IF ls_sug-old_text IS NOT INITIAL.
        lv_line = lv_line && |Current text: { quote( ls_sug-old_text ) }. |.
      ENDIF.
      lv_line = lv_line && |Max length { COND i( WHEN ls_sug-new_length > 0 THEN ls_sug-new_length ELSE ls_sug-max_len ) }. |
             && |Answer with text_suggest and replaces_id={ ls_sug-id }.|.
      rv_text = rv_text && lv_line && cl_abap_char_utilities=>newline.
    ENDLOOP.
    IF rv_text IS INITIAL.
      rv_text = '(none)'.
    ENDIF.
  ENDMETHOD.

  METHOD add_feedback.
    APPEND VALUE ty_feedback( id = iv_id kind = iv_kind text = iv_text prompt = iv_prompt ) TO mt_feedback.
  ENDMETHOD.

  METHOD take_feedback.
    LOOP AT mt_feedback ASSIGNING FIELD-SYMBOL(<ls_fb>) WHERE delivered = abap_false.
      rv_text = rv_text && <ls_fb>-text && cl_abap_char_utilities=>newline.
      <ls_fb>-delivered = abap_true.
    ENDLOOP.
    DELETE mt_feedback WHERE delivered = abap_true.
  ENDMETHOD.

  METHOD has_outbox.
    READ TABLE mt_feedback TRANSPORTING NO FIELDS WITH KEY delivered = abap_false prompt = abap_true.
    rv_has = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD take_outbox.
    DATA lv_lines TYPE string.
    LOOP AT mt_feedback ASSIGNING FIELD-SYMBOL(<ls_fb>) WHERE delivered = abap_false AND prompt = abap_true.
      lv_lines = lv_lines && <ls_fb>-text && cl_abap_char_utilities=>newline.
      <ls_fb>-delivered = abap_true.
    ENDLOOP.
    DELETE mt_feedback WHERE delivered = abap_true.
    IF lv_lines IS INITIAL.
      RETURN.
    ENDIF.
    rv_text = `[Text review feedback from the user]` && cl_abap_char_utilities=>newline
      && lv_lines
      && `Answer every request with the tool text_suggest and set replaces_id to the number given. `
      && `Respect the stated maximum length (or raise the defined length of a text symbol with new_length where allowed). `
      && `Do not resubmit unchanged texts and do not touch texts the user did not mention.`.
  ENDMETHOD.

  METHOD note_ai_activity.
    mv_ai_ts   = now( ).
    mv_ai_what = iv_what.
  ENDMETHOD.

  "------------------------------------------------------------------
  " popup
  "------------------------------------------------------------------
  METHOD is_open.
    rv_open = xsdbool( mo_dialog IS BOUND AND mo_html IS BOUND ).
  ENDMETHOD.

  METHOD ensure_popup.
    rv_ok = abap_false.
    IF is_open( ) = abap_true.
      rv_ok = abap_true.
      RETURN.
    ENDIF.
    IF ui_available( ) = abap_false.
      RETURN.
    ENDIF.

    TRY.
        CREATE OBJECT mo_dialog
          EXPORTING
            width                       = gc_width
            height                      = gc_height
            top                         = 30
            left                        = 60
            caption                     = gc_caption
            metric                      = cl_gui_control=>metric_pixel
          EXCEPTIONS
            cntl_error                  = 1
            cntl_system_error           = 2
            create_error                = 3
            lifetime_error              = 4
            lifetime_dynpro_dynpro_link = 5
            event_already_registered    = 6
            error_regist_event          = 7
            OTHERS                      = 8.
        IF sy-subrc <> 0.
          CLEAR mo_dialog.
          set_banner( iv_text = |Review window could not be created (rc={ sy-subrc }).| iv_kind = 'E' ).
          RETURN.
        ENDIF.
        SET HANDLER me->on_close FOR mo_dialog.

        CREATE OBJECT mo_html
          EXPORTING
            parent = mo_dialog
          EXCEPTIONS
            OTHERS = 1.
        IF sy-subrc <> 0.
          CLEAR mo_html.
          mo_dialog->free( EXCEPTIONS OTHERS = 1 ).
          CLEAR mo_dialog.
          set_banner( iv_text = 'HTML viewer could not be created.' iv_kind = 'E' ).
          RETURN.
        ENDIF.

        "Application event: delivered inside a real PAI round trip, so the
        "hosting report can run the dialog actions right after dispatch.
        DATA: lt_events TYPE cntl_simple_events,
              ls_event  TYPE cntl_simple_event.
        ls_event-eventid    = mo_html->m_id_sapevent.
        ls_event-appl_event = abap_true.
        APPEND ls_event TO lt_events.
        mo_html->set_registered_events(
          EXPORTING events = lt_events
          EXCEPTIONS OTHERS = 1 ).
        SET HANDLER me->on_sapevent FOR mo_html.

        mv_user_closed = abap_false.
        rv_ok = abap_true.
      CATCH cx_root INTO DATA(lx_error).
        CLEAR: mo_html, mo_dialog.
        set_banner( iv_text = |Review window error: { lx_error->get_text( ) }| iv_kind = 'E' ).
    ENDTRY.
  ENDMETHOD.

  METHOD show.
    IF ensure_popup( ) = abap_false.
      RETURN.
    ENDIF.
    refresh( iv_anchor ).
  ENDMETHOD.

  METHOD refresh.
    DATA lv_url TYPE char255.
    IF is_open( ) = abap_false.
      RETURN.
    ENDIF.

    TRY.
        DATA(lt_html) = zzwn00224895_ai_texts_html=>build( build_view( ) ).
        CLEAR: mv_status, mv_status_kind.

        mo_html->load_data(
          EXPORTING  type         = 'text'
                     subtype      = 'html'
          IMPORTING  assigned_url = lv_url
          CHANGING   data_table   = lt_html
          EXCEPTIONS OTHERS       = 1 ).
        IF sy-subrc <> 0.
          set_banner( iv_text = |Could not load the review page (rc={ sy-subrc }).| iv_kind = 'E' ).
          RETURN.
        ENDIF.

        DATA lv_target TYPE char255.
        lv_target = lv_url.
        IF iv_anchor IS NOT INITIAL.
          lv_target = |{ lv_url }#{ iv_anchor }|.
        ENDIF.
        mo_html->show_url(
          EXPORTING  url    = lv_target
          EXCEPTIONS OTHERS = 1 ).
        IF sy-subrc <> 0.
          set_banner( iv_text = |Could not display the review page (rc={ sy-subrc }).| iv_kind = 'E' ).
        ENDIF.
      CATCH cx_root INTO DATA(lx_error).
        set_banner( iv_text = |Review page error: { lx_error->get_text( ) }| iv_kind = 'E' ).
    ENDTRY.
  ENDMETHOD.

  METHOD close.
    IF iv_discard = abap_true.
      discard_open( ).
    ENDIF.
    TRY.
        IF mo_html IS BOUND.
          mo_html->free( EXCEPTIONS OTHERS = 1 ).
        ENDIF.
        IF mo_dialog IS BOUND.
          mo_dialog->free( EXCEPTIONS OTHERS = 1 ).
        ENDIF.
      CATCH cx_root.
    ENDTRY.
    CLEAR: mo_html, mo_dialog, ms_pending, mv_has_pending.
  ENDMETHOD.

  METHOD discard_open.
    DATA lv_count TYPE i.
    LOOP AT mt_suggestions ASSIGNING FIELD-SYMBOL(<ls_sug>)
         WHERE status = zzwn00224895_ai_texts_api=>gc_st_pending
            OR status = zzwn00224895_ai_texts_api=>gc_st_accepted
            OR status = zzwn00224895_ai_texts_api=>gc_st_retry
            OR status = zzwn00224895_ai_texts_api=>gc_st_changes
            OR status = zzwn00224895_ai_texts_api=>gc_st_failed.
      <ls_sug>-status       = zzwn00224895_ai_texts_api=>gc_st_refused.
      <ls_sug>-request_open = abap_false.
      <ls_sug>-decided_at   = now( ).
      lv_count = lv_count + 1.
    ENDLOOP.
    mv_user_closed = abap_true.
    IF lv_count > 0.
      add_feedback( iv_id = 0 iv_kind = 'CLOSED' iv_prompt = abap_false
        iv_text = |The user closed the text review and discarded { lv_count } open suggestion(s). |
               && `Stop suggesting texts unless the user asks again.` ).
    ENDIF.
  ENDMETHOD.

  METHOD build_view.
    "--- languages present in originals or suggestions ----------------
    DATA lt_langs TYPE zzwn00224895_ai_texts_api=>tt_view_lang.
    LOOP AT mt_originals INTO DATA(ls_orig).
      READ TABLE lt_langs ASSIGNING FIELD-SYMBOL(<ls_lang>) WITH KEY langu = ls_orig-langu.
      IF sy-subrc <> 0.
        APPEND VALUE #( langu = ls_orig-langu iso = zzwn00224895_ai_texts_api=>iso_of( ls_orig-langu ) ) TO lt_langs ASSIGNING <ls_lang>.
      ENDIF.
      <ls_lang>-count = <ls_lang>-count + 1.
    ENDLOOP.
    LOOP AT mt_suggestions INTO DATA(ls_sug).
      READ TABLE lt_langs TRANSPORTING NO FIELDS WITH KEY langu = ls_sug-langu.
      IF sy-subrc <> 0.
        APPEND VALUE #( langu = ls_sug-langu iso = ls_sug-iso ) TO lt_langs.
      ENDIF.
    ENDLOOP.
    DATA(lt_installed) = zzwn00224895_ai_texts_api=>installed_languages( ).
    LOOP AT lt_langs ASSIGNING <ls_lang>.
      READ TABLE mt_visible INTO DATA(ls_vis) WITH TABLE KEY langu = <ls_lang>-langu.
      <ls_lang>-visible = COND #( WHEN sy-subrc = 0 THEN ls_vis-visible ELSE abap_false ).
      READ TABLE lt_installed INTO DATA(ls_inst) WITH KEY langu = <ls_lang>-langu.
      IF sy-subrc = 0.
        <ls_lang>-name = ls_inst-name.
      ENDIF.
      IF <ls_lang>-name IS INITIAL.
        <ls_lang>-name = <ls_lang>-iso.
      ENDIF.
    ENDLOOP.
    SORT lt_langs BY iso.
    rs_view-langs = lt_langs.

    rs_view-objects     = mt_objects.
    rs_view-originals   = mt_originals.
    rs_view-suggestions = mt_suggestions.

    LOOP AT mt_suggestions INTO ls_sug.
      CASE ls_sug-status.
        WHEN zzwn00224895_ai_texts_api=>gc_st_pending.  rs_view-cnt_pending  = rs_view-cnt_pending + 1.
        WHEN zzwn00224895_ai_texts_api=>gc_st_accepted. rs_view-cnt_accepted = rs_view-cnt_accepted + 1.
        WHEN zzwn00224895_ai_texts_api=>gc_st_applied.  rs_view-cnt_applied  = rs_view-cnt_applied + 1.
        WHEN zzwn00224895_ai_texts_api=>gc_st_retry OR zzwn00224895_ai_texts_api=>gc_st_changes.
          rs_view-cnt_waiting = rs_view-cnt_waiting + 1.
        WHEN zzwn00224895_ai_texts_api=>gc_st_denied OR zzwn00224895_ai_texts_api=>gc_st_refused.
          rs_view-cnt_denied = rs_view-cnt_denied + 1.
      ENDCASE.
    ENDLOOP.

    rs_view-status_msg  = mv_status.
    rs_view-status_kind = mv_status_kind.

    IF mv_ai_ts IS NOT INITIAL.
      TRY.
          DATA(lv_secs) = cl_abap_tstmp=>subtract( tstmp1 = now( ) tstmp2 = mv_ai_ts ).
          DATA lv_age TYPE i.
          lv_age = lv_secs.
          rs_view-ai_note = |AI { mv_ai_what } - { lv_age }s ago|.
        CATCH cx_root.
          rs_view-ai_note = |AI { mv_ai_what }|.
      ENDTRY.
    ENDIF.
  ENDMETHOD.

  "------------------------------------------------------------------
  " events
  "------------------------------------------------------------------
  METHOD on_sapevent.
    parse_event( iv_action = action iv_getdata = getdata it_postdata = postdata ).
    execute_pending( iv_allow_dialog = abap_false ).
  ENDMETHOD.

  METHOD on_close.
    IF sender <> mo_dialog.
      RETURN.
    ENDIF.
    CLEAR ms_pending.
    ms_pending-action = 'CLOSE'.
    mv_has_pending    = abap_true.
    "If the close event arrives as a system event there is no PAI yet;
    "request one so the hosting report reaches PROCESS_PENDING.
    cl_gui_cfw=>set_new_ok_code( new_code = gc_ok_code ).
  ENDMETHOD.

  METHOD parse_event.
    DATA lv_payload TYPE string.
    CLEAR ms_pending.

    ms_pending-action = to_upper( condense( CONV string( iv_action ) ) ).

    LOOP AT it_postdata INTO DATA(ls_line).
      lv_payload = lv_payload && ls_line.
    ENDLOOP.
    IF lv_payload IS INITIAL.
      lv_payload = iv_getdata.
    ELSEIF iv_getdata IS NOT INITIAL.
      lv_payload = lv_payload && '&' && iv_getdata.
    ENDIF.

    DATA(lv_id) = form_value( iv_payload = lv_payload iv_name = 'id' ).
    IF lv_id CO '0123456789' AND lv_id IS NOT INITIAL.
      ms_pending-id = lv_id.
    ENDIF.
    ms_pending-comment = form_value( iv_payload = lv_payload iv_name = 'comment' ).
    IF strlen( ms_pending-comment ) > gc_max_comment.
      ms_pending-comment = ms_pending-comment(gc_max_comment).
    ENDIF.
    ms_pending-value = form_value( iv_payload = lv_payload iv_name = 'l' ).
    IF ms_pending-value IS INITIAL.
      ms_pending-value = form_value( iv_payload = lv_payload iv_name = 'm' ).
    ENDIF.
    mv_has_pending = abap_true.
  ENDMETHOD.

  METHOD form_value.
    DATA: lt_pairs TYPE string_table,
          lv_name  TYPE string,
          lv_value TYPE string.
    SPLIT iv_payload AT '&' INTO TABLE lt_pairs.
    LOOP AT lt_pairs INTO DATA(lv_pair).
      CLEAR: lv_name, lv_value.
      SPLIT lv_pair AT '=' INTO lv_name lv_value.
      IF lv_name = iv_name.
        rv_value = url_decode( lv_value ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD url_decode.
    rv_out = iv_in.
    REPLACE ALL OCCURRENCES OF '+' IN rv_out WITH ` `.
    TRY.
        rv_out = cl_http_utility=>unescape_url( escaped = rv_out ).
      CATCH cx_root.
    ENDTRY.
    "Form posts arrive UTF-8 encoded; undo it when the text contains
    "escaped multi-byte sequences.
    TRY.
        DATA lv_x TYPE xstring.
        DATA lv_utf TYPE string.
        lv_x = cl_abap_codepage=>convert_to( source = rv_out codepage = 'ISO-8859-1' ).
        lv_utf = cl_abap_codepage=>convert_from( source = lv_x codepage = 'UTF-8' ).
        IF lv_utf IS NOT INITIAL.
          rv_out = lv_utf.
        ENDIF.
      CATCH cx_root.
    ENDTRY.
    rv_out = condense( rv_out ).
  ENDMETHOD.

  METHOD needs_dialog.
    rv_needs = xsdbool( iv_action = 'APPLY' OR iv_action = 'APPLY_ALL'
                     OR iv_action = 'APPLY_ACCEPTED' OR iv_action = 'CLOSE' ).
  ENDMETHOD.

  METHOD process_pending.
    execute_pending( iv_allow_dialog = abap_true ).
  ENDMETHOD.

  METHOD execute_pending.
    IF mv_has_pending = abap_false OR mv_in_pending = abap_true.
      RETURN.
    ENDIF.
    IF needs_dialog( ms_pending-action ) = abap_true AND iv_allow_dialog = abap_false.
      "Wait for the hosting report's PAI hook.
      RETURN.
    ENDIF.

    DATA(ls_req) = ms_pending.
    CLEAR ms_pending.
    mv_has_pending = abap_false.
    mv_in_pending  = abap_true.

    DATA lv_anchor TYPE string.
    IF ls_req-id > 0.
      lv_anchor = |s{ ls_req-id }|.
    ENDIF.

    TRY.
        CASE ls_req-action.
          WHEN 'ACCEPT'.
            set_status( iv_id = ls_req-id iv_status = zzwn00224895_ai_texts_api=>gc_st_accepted ).
            set_banner( iv_text = |#{ ls_req-id } accepted. Use "Apply accepted" to write it.| iv_kind = 'I' ).

          WHEN 'APPLY'.
            set_status( iv_id = ls_req-id iv_status = zzwn00224895_ai_texts_api=>gc_st_accepted ).
            apply_ids( VALUE #( ( ls_req-id ) ) ).

          WHEN 'UNDO'.
            READ TABLE mt_suggestions INTO DATA(ls_sug) WITH KEY id = ls_req-id.
            IF sy-subrc = 0 AND ls_sug-status <> zzwn00224895_ai_texts_api=>gc_st_applied
               AND ls_sug-status <> zzwn00224895_ai_texts_api=>gc_st_superseded.
              set_status( iv_id = ls_req-id iv_status = zzwn00224895_ai_texts_api=>gc_st_pending iv_comment = `` ).
            ENDIF.

          WHEN 'RETRY'.
            request_ai( iv_id = ls_req-id iv_kind = 'RETRY' ).
            set_banner( iv_text = |#{ ls_req-id }: the AI is asked for a different suggestion.| iv_kind = 'I' ).

          WHEN 'REQCHG'.
            IF ls_req-comment IS INITIAL.
              set_banner( iv_text = 'Please describe what should change before sending.' iv_kind = 'E' ).
            ELSE.
              request_ai( iv_id = ls_req-id iv_kind = 'CHANGE' iv_comment = ls_req-comment ).
              set_banner( iv_text = |#{ ls_req-id }: change request sent to the AI.| iv_kind = 'I' ).
            ENDIF.

          WHEN 'DENY'.
            IF ls_req-comment IS INITIAL.
              set_banner( iv_text = 'Please give a reason, or use "Refuse" to deny silently.' iv_kind = 'E' ).
            ELSE.
              request_ai( iv_id = ls_req-id iv_kind = 'DENY' iv_comment = ls_req-comment ).
              set_banner( iv_text = |#{ ls_req-id } denied; the AI is informed about the reason.| iv_kind = 'I' ).
            ENDIF.

          WHEN 'REFUSE'.
            set_status( iv_id = ls_req-id iv_status = zzwn00224895_ai_texts_api=>gc_st_refused ).

          WHEN 'ACCEPT_ALL'.
            DATA lv_n TYPE i.
            LOOP AT mt_suggestions INTO ls_sug WHERE status = zzwn00224895_ai_texts_api=>gc_st_pending.
              set_status( iv_id = ls_sug-id iv_status = zzwn00224895_ai_texts_api=>gc_st_accepted ).
              lv_n = lv_n + 1.
            ENDLOOP.
            set_banner( iv_text = |{ lv_n } suggestion(s) accepted. Use "Apply accepted" to write them.| iv_kind = 'I' ).

          WHEN 'APPLY_ACCEPTED' OR 'APPLY_ALL'.
            DATA lt_ids TYPE int4_table.
            LOOP AT mt_suggestions INTO ls_sug.
              IF ls_sug-status = zzwn00224895_ai_texts_api=>gc_st_accepted
                 OR ls_sug-status = zzwn00224895_ai_texts_api=>gc_st_failed
                 OR ( ls_req-action = 'APPLY_ALL' AND ls_sug-status = zzwn00224895_ai_texts_api=>gc_st_pending ).
                set_status( iv_id = ls_sug-id iv_status = zzwn00224895_ai_texts_api=>gc_st_accepted ).
                APPEND ls_sug-id TO lt_ids.
              ENDIF.
            ENDLOOP.
            IF lt_ids IS INITIAL.
              set_banner( iv_text = 'Nothing to apply.' iv_kind = 'I' ).
            ELSE.
              apply_ids( lt_ids ).
            ENDIF.
            CLEAR lv_anchor.

          WHEN 'LANG'.
            toggle_language( ls_req-value ).

          WHEN 'ORIG'.
            set_orig_mode( ls_req-value ).

          WHEN 'REFRESH'.
            CLEAR: mv_status, mv_status_kind.

          WHEN 'CLOSE'.
            IF confirm_close( ) = abap_true.
              close( iv_discard = abap_true ).
            ENDIF.

          WHEN OTHERS.
            "unknown action: ignore
        ENDCASE.
      CATCH cx_root INTO DATA(lx_error).
        set_banner( iv_text = |Action { ls_req-action } failed: { root_cause( lx_error ) }| iv_kind = 'E' ).
    ENDTRY.

    IF is_open( ) = abap_true.
      refresh( lv_anchor ).
    ENDIF.
    mv_in_pending = abap_false.
  ENDMETHOD.

  METHOD confirm_close.
    DATA lv_open TYPE i.
    LOOP AT mt_suggestions TRANSPORTING NO FIELDS
         WHERE status = zzwn00224895_ai_texts_api=>gc_st_pending
            OR status = zzwn00224895_ai_texts_api=>gc_st_accepted
            OR status = zzwn00224895_ai_texts_api=>gc_st_retry
            OR status = zzwn00224895_ai_texts_api=>gc_st_changes
            OR status = zzwn00224895_ai_texts_api=>gc_st_failed.
      lv_open = lv_open + 1.
    ENDLOOP.
    IF lv_open = 0.
      rv_close = abap_true.
      RETURN.
    ENDIF.

    DATA: lv_answer   TYPE c LENGTH 1,
          lv_question TYPE c LENGTH 200.
    lv_question = |{ lv_open } suggestion(s) are not applied yet. Discard them and close the review?|.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Close text review'
        text_question         = lv_question
        text_button_1         = 'Discard'
        icon_button_1         = 'ICON_DELETE'
        text_button_2         = 'Keep open'
        icon_button_2         = 'ICON_CANCEL'
        default_button        = '2'
        display_cancel_button = abap_false
      IMPORTING
        answer                = lv_answer
      EXCEPTIONS
        OTHERS                = 1.
    rv_close = xsdbool( sy-subrc = 0 AND lv_answer = '1' ).
  ENDMETHOD.

  METHOD toggle_language.
    IF iv_iso IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_iso) = CONV laiso( to_upper( iv_iso ) ).
    DATA(lt_installed) = zzwn00224895_ai_texts_api=>installed_languages( ).
    READ TABLE lt_installed INTO DATA(ls_lang) WITH KEY iso = lv_iso.
    IF sy-subrc = 0.
      READ TABLE mt_visible INTO DATA(ls_vis) WITH TABLE KEY langu = ls_lang-langu.
      DATA(lv_new) = COND abap_bool( WHEN sy-subrc = 0 AND ls_vis-visible = abap_true THEN abap_false ELSE abap_true ).
      set_language_visible( iv_langu = ls_lang-langu iv_visible = lv_new ).
      RETURN.
    ENDIF.
    "Language of a suggestion that is not installed any more / unknown ISO.
    LOOP AT mt_suggestions INTO DATA(ls_sug) WHERE iso = lv_iso.
      READ TABLE mt_visible INTO ls_vis WITH TABLE KEY langu = ls_sug-langu.
      lv_new = COND abap_bool( WHEN sy-subrc = 0 AND ls_vis-visible = abap_true THEN abap_false ELSE abap_true ).
      set_language_visible( iv_langu = ls_sug-langu iv_visible = lv_new ).
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD set_orig_mode.
    CASE to_upper( iv_mode ).
      WHEN 'A'.
        LOOP AT mt_visible ASSIGNING FIELD-SYMBOL(<ls_vis>).
          <ls_vis>-visible = abap_true.
        ENDLOOP.
      WHEN 'N'.
        LOOP AT mt_visible ASSIGNING <ls_vis>.
          <ls_vis>-visible = abap_false.
        ENDLOOP.
      WHEN 'M'.
        LOOP AT mt_visible ASSIGNING <ls_vis>.
          <ls_vis>-visible = abap_false.
        ENDLOOP.
        LOOP AT mt_objects INTO DATA(ls_obj).
          set_language_visible( iv_langu = ls_obj-master_lang iv_visible = abap_true ).
        ENDLOOP.
    ENDCASE.
  ENDMETHOD.

  METHOD set_status.
    READ TABLE mt_suggestions ASSIGNING FIELD-SYMBOL(<ls_sug>) WITH KEY id = iv_id.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    IF <ls_sug>-status = zzwn00224895_ai_texts_api=>gc_st_applied
       AND iv_status <> zzwn00224895_ai_texts_api=>gc_st_applied.
      RETURN.  "written texts cannot change state any more
    ENDIF.
    <ls_sug>-status     = iv_status.
    <ls_sug>-decided_at = now( ).
    IF iv_comment IS SUPPLIED.
      <ls_sug>-comment = iv_comment.
    ENDIF.
    IF iv_status = zzwn00224895_ai_texts_api=>gc_st_pending.
      CLEAR: <ls_sug>-request_open, <ls_sug>-request_kind, <ls_sug>-error.
    ENDIF.
  ENDMETHOD.

  METHOD request_ai.
    READ TABLE mt_suggestions ASSIGNING FIELD-SYMBOL(<ls_sug>) WITH KEY id = iv_id.
    IF sy-subrc <> 0 OR <ls_sug>-status = zzwn00224895_ai_texts_api=>gc_st_applied.
      RETURN.
    ENDIF.

    <ls_sug>-request_open = abap_true.
    <ls_sug>-request_kind = iv_kind.
    <ls_sug>-comment      = iv_comment.
    <ls_sug>-decided_at   = now( ).

    DATA lv_text TYPE string.
    DATA(lv_limit) = COND i( WHEN <ls_sug>-new_length > 0 THEN <ls_sug>-new_length ELSE <ls_sug>-max_len ).
    DATA(lv_what)  = describe( <ls_sug> ).
    DATA(lv_prev)  = COND string( WHEN <ls_sug>-action = zzwn00224895_ai_texts_api=>gc_act_delete
                                  THEN |delete { quote( <ls_sug>-old_text ) }|
                                  ELSE quote( <ls_sug>-new_text ) ).
    DATA(lv_cur)   = COND string( WHEN <ls_sug>-old_text IS INITIAL THEN `(none)` ELSE quote( <ls_sug>-old_text ) ).

    CASE iv_kind.
      WHEN 'RETRY'.
        <ls_sug>-status = zzwn00224895_ai_texts_api=>gc_st_retry.
        lv_text = |#{ iv_id } RETRY requested for { lv_what }. Rejected suggestion: { lv_prev }. Current text: { lv_cur }. |
               && |Max length { lv_limit }. Provide a clearly different text via text_suggest (replaces_id={ iv_id }).|.
      WHEN 'CHANGE'.
        <ls_sug>-status = zzwn00224895_ai_texts_api=>gc_st_changes.
        lv_text = |#{ iv_id } CHANGES requested for { lv_what }. User comment: { quote( iv_comment ) }. |
               && |Rejected suggestion: { lv_prev }. Current text: { lv_cur }. Max length { lv_limit }. |
               && |Provide an improved text via text_suggest (replaces_id={ iv_id }).|.
      WHEN OTHERS.
        <ls_sug>-status = zzwn00224895_ai_texts_api=>gc_st_denied.
        lv_text = |#{ iv_id } DENIED for { lv_what }. Reason: { quote( iv_comment ) }. Rejected suggestion: { lv_prev }. |
               && |If the reason can be addressed, provide an improved text via text_suggest (replaces_id={ iv_id }); |
               && |otherwise leave this text unchanged.|.
    ENDCASE.
    add_feedback( iv_id = iv_id iv_kind = iv_kind iv_text = lv_text iv_prompt = abap_true ).
  ENDMETHOD.

  "------------------------------------------------------------------
  " apply
  "------------------------------------------------------------------
  METHOD apply_ids.
    DATA lt_groups TYPE tt_group.

    "Group by object and language: one text pool write per group, the
    "newest accepted suggestion wins when two target the same text.
    LOOP AT it_ids INTO DATA(lv_id).
      READ TABLE mt_suggestions ASSIGNING FIELD-SYMBOL(<ls_sug>) WITH KEY id = lv_id.
      IF sy-subrc <> 0 OR <ls_sug>-status <> zzwn00224895_ai_texts_api=>gc_st_accepted.
        CONTINUE.
      ENDIF.

      READ TABLE lt_groups ASSIGNING FIELD-SYMBOL(<ls_grp>)
        WITH TABLE KEY obj_type = <ls_sug>-obj_type obj_name = <ls_sug>-obj_name langu = <ls_sug>-langu.
      IF sy-subrc <> 0.
        INSERT VALUE ty_group( obj_type = <ls_sug>-obj_type obj_name = <ls_sug>-obj_name langu = <ls_sug>-langu )
          INTO TABLE lt_groups ASSIGNING <ls_grp>.
      ENDIF.

      READ TABLE <ls_grp>-changes ASSIGNING FIELD-SYMBOL(<ls_chg>)
        WITH KEY text_id = <ls_sug>-text_id text_key = <ls_sug>-text_key.
      IF sy-subrc = 0.
        "Conflict inside one write: the earlier one becomes superseded.
        DATA lt_remove TYPE int4_table.
        CLEAR lt_remove.
        LOOP AT <ls_grp>-ids INTO DATA(lv_other).
          READ TABLE mt_suggestions ASSIGNING FIELD-SYMBOL(<ls_prev>) WITH KEY id = lv_other.
          IF sy-subrc = 0 AND <ls_prev>-text_id = <ls_sug>-text_id AND <ls_prev>-text_key = <ls_sug>-text_key.
            <ls_prev>-status      = zzwn00224895_ai_texts_api=>gc_st_superseded.
            <ls_prev>-replaced_by = <ls_sug>-id.
            APPEND lv_other TO lt_remove.
          ENDIF.
        ENDLOOP.
        LOOP AT lt_remove INTO lv_other.
          DELETE <ls_grp>-ids WHERE table_line = lv_other.
        ENDLOOP.
      ELSE.
        APPEND INITIAL LINE TO <ls_grp>-changes ASSIGNING <ls_chg>.
      ENDIF.
      <ls_chg>-text_id  = <ls_sug>-text_id.
      <ls_chg>-text_key = <ls_sug>-text_key.
      <ls_chg>-delete   = xsdbool( <ls_sug>-action = zzwn00224895_ai_texts_api=>gc_act_delete ).
      <ls_chg>-text     = <ls_sug>-new_text.
      <ls_chg>-length   = <ls_sug>-new_length.
      <ls_chg>-prefix   = <ls_sug>-prefix.
      APPEND <ls_sug>-id TO <ls_grp>-ids.

      "A longer defined length of a text symbol must also be raised in
      "the master language row, otherwise SE38/SE63 shrink it back.
      IF <ls_sug>-obj_type = zzwn00224895_ai_texts_api=>gc_obj_prog
         AND <ls_sug>-text_id = zzwn00224895_ai_texts_api=>gc_id_symbol
         AND <ls_sug>-new_length > 0 AND <ls_chg>-delete = abap_false.
        READ TABLE mt_objects INTO DATA(ls_obj)
          WITH KEY obj_type = <ls_sug>-obj_type obj_name = <ls_sug>-obj_name.
        IF sy-subrc = 0 AND ls_obj-master_lang <> <ls_sug>-langu.
          find_original(
            EXPORTING iv_obj_type = <ls_sug>-obj_type iv_obj_name = <ls_sug>-obj_name
                      iv_text_id = <ls_sug>-text_id iv_text_key = <ls_sug>-text_key
                      iv_langu = ls_obj-master_lang
            IMPORTING es_text = DATA(ls_master) ev_found = DATA(lv_found) ).
          IF lv_found = abap_true AND ls_master-length < <ls_sug>-new_length.
            READ TABLE lt_groups ASSIGNING FIELD-SYMBOL(<ls_mgrp>)
              WITH TABLE KEY obj_type = <ls_sug>-obj_type obj_name = <ls_sug>-obj_name langu = ls_obj-master_lang.
            IF sy-subrc <> 0.
              INSERT VALUE ty_group( obj_type = <ls_sug>-obj_type obj_name = <ls_sug>-obj_name langu = ls_obj-master_lang )
                INTO TABLE lt_groups ASSIGNING <ls_mgrp>.
            ENDIF.
            READ TABLE <ls_mgrp>-changes TRANSPORTING NO FIELDS
              WITH KEY text_id = <ls_sug>-text_id text_key = <ls_sug>-text_key.
            IF sy-subrc <> 0.
              APPEND VALUE zzwn00224895_ai_texts_api=>ty_change(
                text_id = <ls_sug>-text_id text_key = <ls_sug>-text_key
                text = ls_master-text length = <ls_sug>-new_length ) TO <ls_mgrp>-changes.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.

    DATA: lv_ok_cnt  TYPE i,
          lv_err_cnt TYPE i,
          lv_last_rq TYPE trkorr.
    LOOP AT lt_groups ASSIGNING <ls_grp>.
      apply_group( CHANGING cs_group = <ls_grp> ).
      LOOP AT <ls_grp>-ids INTO lv_id.
        READ TABLE mt_suggestions INTO DATA(ls_done) WITH KEY id = lv_id.
        IF sy-subrc = 0.
          IF ls_done-status = zzwn00224895_ai_texts_api=>gc_st_applied.
            lv_ok_cnt = lv_ok_cnt + 1.
            IF ls_done-request IS NOT INITIAL.
              lv_last_rq = ls_done-request.
            ENDIF.
          ELSEIF ls_done-status = zzwn00224895_ai_texts_api=>gc_st_failed.
            lv_err_cnt = lv_err_cnt + 1.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    IF lv_err_cnt = 0 AND lv_ok_cnt > 0.
      DATA(lv_msg) = |{ lv_ok_cnt } text(s) written to the system.|.
      IF lv_last_rq IS NOT INITIAL.
        lv_msg = lv_msg && | Transport request { lv_last_rq }.|.
      ENDIF.
      set_banner( iv_text = lv_msg iv_kind = 'S' ).
    ELSEIF lv_ok_cnt > 0.
      set_banner( iv_text = |{ lv_ok_cnt } text(s) written, { lv_err_cnt } failed - see the rows marked "apply failed".| iv_kind = 'E' ).
    ELSEIF lv_err_cnt > 0.
      set_banner( iv_text = |Nothing written: { lv_err_cnt } write(s) failed - see the rows marked "apply failed".| iv_kind = 'E' ).
    ENDIF.

    IF lv_ok_cnt > 0.
      DATA lv_ids TYPE string.
      LOOP AT lt_groups ASSIGNING <ls_grp>.
        LOOP AT <ls_grp>-ids INTO lv_id.
          READ TABLE mt_suggestions TRANSPORTING NO FIELDS
            WITH KEY id = lv_id status = zzwn00224895_ai_texts_api=>gc_st_applied.
          IF sy-subrc = 0.
            lv_ids = COND #( WHEN lv_ids IS INITIAL THEN |#{ lv_id }| ELSE |{ lv_ids }, #{ lv_id }| ).
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      add_feedback( iv_id = 0 iv_kind = 'APPLIED' iv_prompt = abap_false
        iv_text = |The user accepted and applied suggestion(s) { lv_ids } to the system.| ).
    ENDIF.
  ENDMETHOD.

  METHOD apply_group.
    DATA: lv_ok      TYPE abap_bool,
          lv_error   TYPE string,
          lv_request TYPE trkorr.
    TRY.
        zzwn00224895_ai_texts_api=>write_texts(
          EXPORTING iv_obj_type = cs_group-obj_type
                    iv_obj_name = cs_group-obj_name
                    iv_langu    = cs_group-langu
                    it_changes  = cs_group-changes
          IMPORTING ev_ok       = lv_ok
                    ev_error    = lv_error
                    ev_request  = lv_request ).
      CATCH cx_root INTO DATA(lx_write).
        lv_ok    = abap_false.
        lv_error = |Write failed: { root_cause( lx_write ) }|.
    ENDTRY.

    LOOP AT cs_group-ids INTO DATA(lv_id).
      READ TABLE mt_suggestions ASSIGNING FIELD-SYMBOL(<ls_sug>) WITH KEY id = lv_id.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      IF lv_ok = abap_true.
        <ls_sug>-status     = zzwn00224895_ai_texts_api=>gc_st_applied.
        <ls_sug>-request    = lv_request.
        <ls_sug>-decided_at = now( ).
        CLEAR: <ls_sug>-error, <ls_sug>-request_open.
      ELSE.
        <ls_sug>-status = zzwn00224895_ai_texts_api=>gc_st_failed.
        <ls_sug>-error  = lv_error.
      ENDIF.
    ENDLOOP.

    IF lv_ok = abap_true.
      "Refresh the originals so the popup shows the new current texts. The
      "texts are already written; a reload problem must not undo that.
      TRY.
          load_object( EXPORTING iv_obj_type = cs_group-obj_type iv_obj_name = cs_group-obj_name iv_force = abap_true ).
        CATCH cx_root INTO DATA(lx_reload).
          set_banner( iv_text = |Texts written, but reloading { cs_group-obj_type } { cs_group-obj_name } failed: |
                              && root_cause( lx_reload ) iv_kind = 'E' ).
      ENDTRY.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
