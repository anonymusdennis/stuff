*&---------------------------------------------------------------------*
*& Extension of report ZZWN00224895_AI for the text review popup
*& (classes ZZWN00224895_AI_TEXTS_*). Three small insertions.
*&
*& Why the hook is needed: the review window is a modeless dialog box on
*& top of screen 0100. Its SAPEVENTs (application events) trigger PAI of
*& 0100. Actions that only change state repaint the window from inside
*& the event handler; actions that open dialogs (transport request popup
*& on "apply", confirmation on "close") must run in plain PAI context ->
*& PROCESS_PENDING. User requests to the AI (retry / change request /
*& deny with reason) become a user message when the assistant is idle ->
*& DELIVER_TEXT_REVIEW. While a turn is running the tool results carry
*& them instead, so nothing is delivered twice.
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* 1) Include ZZWN00224895_AI_CDEF - class lcl_app, PRIVATE SECTION:
*    add one method declaration (e.g. after "METHODS copy_message ...").
*----------------------------------------------------------------------*
*  "Text review popup: hand the user's requests to the assistant when it
*  "is idle (see ZZWN00224895_AI_TEXTS_REVIEW).
*  METHODS deliver_text_review.

*----------------------------------------------------------------------*
* 2) Include ZZWN00224895_AI_CIMP - METHOD pai_0100:
*    replace the CASE statement with this version (two insertions marked
*    with ">>>").
*----------------------------------------------------------------------*
*    CASE iv_ucomm.
*      WHEN 'BACK' OR 'EXIT' OR 'CANC'.
*        ">>> free the review popup together with the chat controls
*        zzwn00224895_ai_texts_review=>get( )->close( ).
*        IF mo_timer IS BOUND.     mo_timer->free( ).     ENDIF.
*        IF mo_cmp_html IS BOUND.  mo_cmp_html->free( ).  CLEAR mo_cmp_html.  ENDIF.
*        IF mo_cmp_cont IS BOUND.  mo_cmp_cont->free( ).  CLEAR mo_cmp_cont.  ENDIF.
*        IF mo_html IS BOUND.      mo_html->free( ).      ENDIF.
*        IF mo_container IS BOUND. mo_container->free( ). ENDIF.
*        LEAVE TO SCREEN 0.
*      WHEN 'SEND'.
*        CLEAR mv_error.
*        mv_pending_action = 'CLIP_SEND'.
*        process_pending( ).
*      WHEN OTHERS.
*        process_pending( ).
*        ">>> text review popup: dialog actions (apply / close) run here in
*        ">>> plain PAI context; then deliver the user's AI requests.
*        zzwn00224895_ai_texts_review=>get( )->process_pending( ).
*        deliver_text_review( ).
*    ENDCASE.

*----------------------------------------------------------------------*
* 3) Include ZZWN00224895_AI_CIMP - METHOD on_timer, last ELSE branch
*    ("Turn finished"): deliver queued review requests before repainting.
*----------------------------------------------------------------------*
*    ELSE.
*      mv_busy = abap_false.
*      ">>> requests from the text review that arrived during the turn
*      deliver_text_review( ).
*      refresh_html( ).
*    ENDIF.

*----------------------------------------------------------------------*
* 4) Include ZZWN00224895_AI_CIMP - new method (inside CLASS lcl_app
*    IMPLEMENTATION, e.g. after METHOD copy_message).
*----------------------------------------------------------------------*
  METHOD deliver_text_review.
    "Coop mode of the text review popup: the user's retry / change /
    "deny-with-reason decisions become one user message as soon as the
    "assistant is idle. A running turn receives them through the text
    "tool results instead (TAKE_FEEDBACK), so the queue is drained once.
    IF mv_busy = abap_true.
      RETURN.
    ENDIF.
    DATA(lo_review) = zzwn00224895_ai_texts_review=>get( ).
    IF lo_review->has_outbox( ) = abap_false.
      RETURN.
    ENDIF.
    DATA(lv_text) = lo_review->take_outbox( ).
    IF lv_text IS INITIAL.
      RETURN.
    ENDIF.
    CLEAR mv_error.
    submit_user_text( lv_text ).
  ENDMETHOD.
