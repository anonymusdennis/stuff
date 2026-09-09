CLASS zzwn00224895_ai_texts_html DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  "===================================================================
  " Renders the text review popup for CL_GUI_HTML_VIEWER.
  "
  " Every user action is a SAPEVENT link or a tiny SAPEVENT form POST
  " (id + comment <= 600 chars, far below the 800 char postdata limit of
  " the target GUI). Nothing depends on JavaScript: the filter box is the
  " only script and the page works without it.
  "
  " CSS/JS are written as classic literals joined with && on purpose:
  " string templates treat { } | \ specially and break embedded CSS.
  " All dynamic text is HTML-escaped; non-ASCII characters become numeric
  " entities so the page renders correctly regardless of the GUI codepage.
  "===================================================================
  PUBLIC SECTION.
    CLASS-METHODS build
      IMPORTING is_view        TYPE zzwn00224895_ai_texts_api=>ty_view
      RETURNING VALUE(rt_html) TYPE w3htmltab.

    CLASS-METHODS esc
      IMPORTING iv_text        TYPE csequence
      RETURNING VALUE(rv_html) TYPE string.

    "Split a long string into 255-char rows without losing significant
    "blanks at row boundaries (fixed-length rows drop trailing blanks).
    CLASS-METHODS to_table
      IMPORTING iv_html        TYPE string
      RETURNING VALUE(rt_html) TYPE w3htmltab.

  PRIVATE SECTION.
    CONSTANTS gc_ascii TYPE string VALUE ` !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_abcdefghijklmnopqrstuvwxyz{|}~`.
    CONSTANTS gc_max_comment TYPE i VALUE 600.

    CLASS-DATA gv_out TYPE string.

    CLASS-METHODS add
      IMPORTING iv_html TYPE string.

    CLASS-METHODS head.
    CLASS-METHODS header
      IMPORTING is_view TYPE zzwn00224895_ai_texts_api=>ty_view.
    CLASS-METHODS groups
      IMPORTING is_view TYPE zzwn00224895_ai_texts_api=>ty_view.
    CLASS-METHODS text_block
      IMPORTING is_view      TYPE zzwn00224895_ai_texts_api=>ty_view
                is_object    TYPE zzwn00224895_ai_texts_api=>ty_object
                iv_text_id   TYPE char1
                iv_text_key  TYPE char8.
    CLASS-METHODS suggestion
      IMPORTING is_sug TYPE zzwn00224895_ai_texts_api=>ty_suggestion.
    CLASS-METHODS buttons
      IMPORTING is_sug TYPE zzwn00224895_ai_texts_api=>ty_suggestion.
    CLASS-METHODS comment_form
      IMPORTING iv_action  TYPE string
                iv_id      TYPE i
                iv_label   TYPE string
                iv_class   TYPE string
                iv_hint    TYPE string
                iv_submit  TYPE string.
    CLASS-METHODS footer
      IMPORTING is_view TYPE zzwn00224895_ai_texts_api=>ty_view.
    CLASS-METHODS link
      IMPORTING iv_action      TYPE string
                iv_label       TYPE string
                iv_class       TYPE string DEFAULT ''
                iv_title       TYPE string DEFAULT ''
      RETURNING VALUE(rv_html) TYPE string.
    CLASS-METHODS len_html
      IMPORTING iv_len         TYPE i
                iv_limit       TYPE i
                iv_hard        TYPE i
      RETURNING VALUE(rv_html) TYPE string.
    CLASS-METHODS text_order
      IMPORTING iv_text_id      TYPE char1
      RETURNING VALUE(rv_order) TYPE i.
ENDCLASS.


CLASS zzwn00224895_ai_texts_html IMPLEMENTATION.

  METHOD add.
    gv_out = gv_out && iv_html.
  ENDMETHOD.

  METHOD esc.
    rv_html = escape( val = CONV string( iv_text ) format = cl_abap_format=>e_html_attr ).
    IF rv_html CO gc_ascii.
      RETURN.
    ENDIF.
    "Non-ASCII present: encode those characters as numeric entities.
    DATA: lv_out TYPE string,
          lv_pos TYPE i,
          lv_len TYPE i,
          lv_ch  TYPE c LENGTH 1.
    lv_len = strlen( rv_html ).
    WHILE lv_pos < lv_len.
      lv_ch = rv_html+lv_pos(1).
      IF lv_ch CO gc_ascii.
        lv_out = lv_out && lv_ch.
      ELSE.
        DATA(lv_code) = cl_abap_conv_in_ce=>uccpi( lv_ch ).
        lv_out = lv_out && '&#' && |{ lv_code }| && ';'.
      ENDIF.
      lv_pos = lv_pos + 1.
    ENDWHILE.
    rv_html = lv_out.
  ENDMETHOD.

  METHOD to_table.
    DATA: ls_row  TYPE w3html,
          lv_rest TYPE string,
          lv_cut  TYPE i.
    lv_rest = iv_html.
    WHILE strlen( lv_rest ) > 0.
      CLEAR ls_row.
      IF strlen( lv_rest ) <= 255.
        ls_row-line = lv_rest.
        APPEND ls_row TO rt_html.
        EXIT.
      ENDIF.
      lv_cut = 255.
      "Never end a row with a blank: it would be lost in the char255 row.
      WHILE lv_cut > 1 AND substring( val = lv_rest off = lv_cut - 1 len = 1 ) = ` `.
        lv_cut = lv_cut - 1.
      ENDWHILE.
      ls_row-line = lv_rest(lv_cut).
      APPEND ls_row TO rt_html.
      lv_rest = lv_rest+lv_cut.
    ENDWHILE.
  ENDMETHOD.

  METHOD link.
    rv_html = '<a class="b ' && iv_class && '" href="SAPEVENT:' && iv_action && '"'.
    IF iv_title IS NOT INITIAL.
      rv_html = rv_html && ' title="' && esc( iv_title ) && '"'.
    ENDIF.
    rv_html = rv_html && '>' && iv_label && '</a>'.
  ENDMETHOD.

  METHOD len_html.
    DATA(lv_class) = COND string( WHEN iv_len > iv_limit THEN 'len bad' ELSE 'len' ).
    rv_html = '<span class="' && lv_class && '" title="length / defined length (hard maximum '
      && |{ iv_hard }| && ')">' && |{ iv_len }/{ iv_limit }| && '</span>'.
  ENDMETHOD.

  METHOD text_order.
    CASE iv_text_id.
      WHEN zzwn00224895_ai_texts_api=>gc_id_title.     rv_order = 1.
      WHEN zzwn00224895_ai_texts_api=>gc_id_symbol.    rv_order = 2.
      WHEN zzwn00224895_ai_texts_api=>gc_id_seltext.   rv_order = 3.
      WHEN zzwn00224895_ai_texts_api=>gc_id_heading.   rv_order = 4.
      WHEN zzwn00224895_ai_texts_api=>gc_id_listtitle. rv_order = 5.
      WHEN OTHERS.                                     rv_order = 9.
    ENDCASE.
  ENDMETHOD.

  METHOD build.
    CLEAR gv_out.
    head( ).
    add( '<body>' ).
    header( is_view ).
    groups( is_view ).
    footer( is_view ).
    add( '<a id="bottom"></a>' ).
    add( '<script>function flt(){var q=document.getElementById("q").value.toLowerCase();'
      && 'var g=document.getElementsByClassName("txt");for(var i=0;i<g.length;i++){'
      && 'var k=g[i].getAttribute("data-k")||"";g[i].style.display=(q===""||k.indexOf(q)>=0)?"":"none";}}</script>' ).
    add( '</body></html>' ).
    rt_html = to_table( gv_out ).
    CLEAR gv_out.
  ENDMETHOD.

  METHOD head.
    add( '<!DOCTYPE html><html><head><meta http-equiv="X-UA-Compatible" content="IE=edge">'
      && '<meta charset="utf-8"><title>AI text review</title><style>' ).
    add( 'body{margin:0;background:#1e1e2e;color:#cdd6f4;font:13px/1.4 "Segoe UI",system-ui,sans-serif}'
      && 'a{color:#89b4fa;text-decoration:none}'
      && '.top{position:sticky;top:0;background:#181825;border-bottom:1px solid #45475a;padding:8px 12px;z-index:5}'
      && '.ttl{font-size:16px;font-weight:600;display:flex;align-items:center;gap:10px;flex-wrap:wrap}'
      && '.cnt{font-size:12px;color:#a6adc8;font-weight:400}'
      && '.ai{font-size:11px;color:#cba6f7;font-weight:400}'
      && '.bar{margin-top:6px;display:flex;flex-wrap:wrap;gap:6px;align-items:center}' ).
    add( '.b{display:inline-block;padding:3px 9px;border-radius:5px;border:1px solid #45475a;background:#313244;'
      && 'color:#cdd6f4;font-size:12px;cursor:pointer;white-space:nowrap}'
      && '.b:hover{border-color:#89b4fa}'
      && '.b.ok{border-color:#a6e3a1;color:#a6e3a1}'
      && '.b.go{background:#a6e3a1;color:#1e1e2e;border-color:#a6e3a1;font-weight:600}'
      && '.b.no{border-color:#f38ba8;color:#f38ba8}'
      && '.b.ask{border-color:#cba6f7;color:#cba6f7}'
      && '.b.mut{color:#a6adc8}' ).
    add( '.ban{margin-top:6px;padding:6px 10px;border-radius:5px;font-size:12px}'
      && '.ban.E{background:#45222e;color:#f38ba8}.ban.S{background:#22402a;color:#a6e3a1}.ban.I{background:#2a3a55;color:#89b4fa}'
      && '.langs{margin-top:6px;font-size:12px;color:#a6adc8;display:flex;flex-wrap:wrap;gap:4px;align-items:center}'
      && '.lg{display:inline-block;padding:1px 6px;border-radius:4px;border:1px solid #45475a;font-size:11px;font-weight:600;color:#cdd6f4}'
      && '.lg.on{background:#89b4fa;color:#1e1e2e;border-color:#89b4fa}'
      && '.lg.off{opacity:.5}'
      && '#q{margin-top:6px;width:100%;box-sizing:border-box;padding:5px 8px;border-radius:5px;border:1px solid #45475a;'
      && 'background:#1e1e2e;color:#cdd6f4}' ).
    add( '.grp{margin:10px 12px}'
      && '.gh{font-weight:600;font-size:14px;padding:6px 0;border-bottom:1px solid #45475a;color:#f9e2af}'
      && '.gh small{color:#a6adc8;font-weight:400;margin-left:8px}'
      && '.txt{margin:8px 0;border:1px solid #45475a;border-radius:6px;overflow:hidden}'
      && '.th{background:#313244;padding:4px 10px;font-size:12px;display:flex;gap:10px;align-items:center;flex-wrap:wrap}'
      && '.th b{color:#94e2d5}'
      && '.orig{padding:4px 10px;display:flex;flex-wrap:wrap;gap:6px 14px;color:#a6adc8;font-size:12px}'
      && '.orig .t{color:#cdd6f4}'
      && '.len{color:#a6adc8;font-size:11px;margin-left:4px}'
      && '.len.bad{color:#f38ba8;font-weight:600}' ).
    add( '.sug{padding:6px 10px;border-top:1px dashed #45475a;display:flex;gap:10px;align-items:flex-start}'
      && '.sug.P{background:#1e1e2e}.sug.A{background:#1f2e26}.sug.X{background:#1b2a1f}'
      && '.sug.D,.sug.R{opacity:.6}.sug.S{opacity:.45}.sug.T,.sug.C{background:#2b2440}.sug.F{background:#3a2028}'
      && '.sid{min-width:42px;color:#a6adc8;font-size:11px;padding-top:2px}'
      && '.body{flex:1;min-width:0}'
      && '.new{font-size:13px;word-break:break-word}'
      && '.new.del{text-decoration:line-through;color:#f38ba8}'
      && '.was{font-size:11px;color:#a6adc8;margin-top:2px}'
      && '.rat{font-size:11px;color:#a6adc8;font-style:italic;margin-top:2px}'
      && '.st{font-size:11px;margin-top:4px;color:#f9e2af}'
      && '.st.err{color:#f38ba8}.st.ok{color:#a6e3a1}'
      && '.acts{display:flex;flex-wrap:wrap;gap:4px;margin-top:6px;align-items:center}' ).
    add( '.act{display:inline-block;padding:1px 6px;border-radius:4px;font-size:10px;font-weight:700;text-transform:uppercase}'
      && '.act.ADD{background:#2a3a55;color:#89b4fa}.act.CHANGE{background:#3a3520;color:#f9e2af}.act.DELETE{background:#45222e;color:#f38ba8}'
      && 'details.frm{display:inline-block}'
      && 'details.frm summary{list-style:none;cursor:pointer}'
      && 'details.frm summary::-webkit-details-marker{display:none}'
      && 'details.frm form{display:flex;gap:4px;margin-top:4px;align-items:flex-start;flex-wrap:wrap}'
      && 'textarea{background:#181825;color:#cdd6f4;border:1px solid #45475a;border-radius:5px;padding:4px;'
      && 'font:12px "Segoe UI",system-ui,sans-serif;width:340px;max-width:100%}'
      && 'input[type=submit]{padding:3px 9px;border-radius:5px;border:1px solid #cba6f7;background:#313244;color:#cba6f7;font-size:12px;cursor:pointer}'
      && '.foot{position:sticky;bottom:0;background:#181825;border-top:1px solid #45475a;padding:8px 12px;display:flex;flex-wrap:wrap;gap:6px;align-items:center}'
      && '.foot .sp{flex:1}'
      && '.empty{margin:30px 12px;color:#a6adc8;text-align:center}' ).
    add( '</style></head>' ).
  ENDMETHOD.

  METHOD header.
    add( '<div class="top"><div class="ttl">AI text review' ).
    add( '<span class="cnt">' && |{ is_view-cnt_pending } pending &middot; { is_view-cnt_accepted } accepted &middot; |
      && |{ is_view-cnt_applied } applied &middot; { is_view-cnt_waiting } waiting for AI &middot; { is_view-cnt_denied } denied|
      && '</span>' ).
    IF is_view-ai_note IS NOT INITIAL.
      add( '<span class="ai">' && esc( is_view-ai_note ) && '</span>' ).
    ENDIF.
    add( '</div>' ).

    add( '<div class="bar">' ).
    add( link( iv_action = 'REFRESH' iv_label = '&#8635; Refresh' iv_class = 'mut' iv_title = 'Repaint the list' ) ).
    add( link( iv_action = 'ACCEPT_ALL' iv_label = 'Accept all pending' iv_class = 'ok'
               iv_title = 'Mark every pending suggestion as accepted (nothing is written yet)' ) ).
    add( link( iv_action = 'APPLY_ACCEPTED' iv_label = 'Apply accepted' iv_class = 'ok'
               iv_title = 'Write all accepted suggestions to the system' ) ).
    add( link( iv_action = 'APPLY_ALL' iv_label = 'Accept &amp; apply all' iv_class = 'go'
               iv_title = 'Accept every pending suggestion and write everything to the system' ) ).
    add( link( iv_action = 'CLOSE' iv_label = 'Close' iv_class = 'no' iv_title = 'Close the review (asks for confirmation)' ) ).
    add( '</div>' ).

    IF is_view-status_msg IS NOT INITIAL.
      DATA(lv_kind) = COND string( WHEN is_view-status_kind IS INITIAL THEN 'I' ELSE CONV string( is_view-status_kind ) ).
      add( '<div class="ban ' && lv_kind && '">' && esc( is_view-status_msg ) && '</div>' ).
    ENDIF.

    add( '<div class="langs">Original texts shown in:' ).
    LOOP AT is_view-langs INTO DATA(ls_lang).
      DATA(lv_cls) = COND string( WHEN ls_lang-visible = abap_true THEN 'lg on' ELSE 'lg off' ).
      add( '<a class="' && lv_cls && '" href="SAPEVENT:LANG?l=' && esc( ls_lang-iso ) && '" title="'
        && esc( ls_lang-name ) && ' - ' && |{ ls_lang-count }| && ' texts">' && esc( ls_lang-iso ) && '</a>' ).
    ENDLOOP.
    add( ' &nbsp;' && link( iv_action = 'ORIG?m=A' iv_label = 'all' iv_class = 'mut' )
      && link( iv_action = 'ORIG?m=M' iv_label = 'master only' iv_class = 'mut' )
      && link( iv_action = 'ORIG?m=N' iv_label = 'none' iv_class = 'mut' ) ).
    add( '</div>' ).
    add( '<input id="q" type="text" placeholder="Filter by object, key or text..." onkeyup="flt()"></div>' ).
  ENDMETHOD.

  METHOD groups.
    IF is_view-objects IS INITIAL AND is_view-suggestions IS INITIAL.
      add( '<div class="empty">No texts loaded yet. Ask the assistant to list or improve the texts of a program '
        && 'or message class; suggestions appear here while it works.</div>' ).
      RETURN.
    ENDIF.

    TYPES: BEGIN OF ty_key,
             ord      TYPE i,
             text_id  TYPE char1,
             text_key TYPE char8,
           END OF ty_key.
    DATA lt_keys TYPE SORTED TABLE OF ty_key WITH UNIQUE KEY ord text_id text_key.

    LOOP AT is_view-objects INTO DATA(ls_obj).
      CLEAR lt_keys.
      LOOP AT is_view-originals INTO DATA(ls_orig)
           WHERE obj_type = ls_obj-obj_type AND obj_name = ls_obj-obj_name.
        INSERT VALUE ty_key( ord = text_order( ls_orig-text_id ) text_id = ls_orig-text_id text_key = ls_orig-text_key )
          INTO TABLE lt_keys.
      ENDLOOP.
      LOOP AT is_view-suggestions INTO DATA(ls_sug)
           WHERE obj_type = ls_obj-obj_type AND obj_name = ls_obj-obj_name.
        INSERT VALUE ty_key( ord = text_order( ls_sug-text_id ) text_id = ls_sug-text_id text_key = ls_sug-text_key )
          INTO TABLE lt_keys.
      ENDLOOP.

      add( '<div class="grp"><div class="gh">' && esc( ls_obj-obj_type ) && ' ' && esc( ls_obj-obj_name ) ).
      add( '<small>' && esc( ls_obj-description ) && '</small><small>master '
        && esc( zzwn00224895_ai_texts_api=>iso_of( ls_obj-master_lang ) ) && '</small>' ).
      IF ls_obj-devclass IS NOT INITIAL.
        add( '<small>' && esc( ls_obj-devclass ) && '</small>' ).
      ENDIF.
      IF ls_obj-exists = abap_false.
        add( '<small style="color:#f38ba8">object does not exist</small>' ).
      ENDIF.
      add( '</div>' ).

      LOOP AT lt_keys INTO DATA(ls_key).
        text_block( is_view = is_view is_object = ls_obj iv_text_id = ls_key-text_id iv_text_key = ls_key-text_key ).
      ENDLOOP.
      add( '</div>' ).
    ENDLOOP.
  ENDMETHOD.

  METHOD text_block.
    DATA: lv_filter TYPE string,
          lv_max    TYPE i,
          lv_limit  TYPE i.

    lv_max = zzwn00224895_ai_texts_api=>max_length( iv_obj_type = is_object-obj_type iv_text_id = iv_text_id ).
    lv_limit = lv_max.
    lv_filter = to_lower( |{ is_object-obj_type } { is_object-obj_name } { iv_text_id } { iv_text_key } | ).

    "Defined length of a text symbol = the master language row (fallback: any row).
    IF iv_text_id = zzwn00224895_ai_texts_api=>gc_id_symbol AND is_object-obj_type = zzwn00224895_ai_texts_api=>gc_obj_prog.
      READ TABLE is_view-originals INTO DATA(ls_master)
        WITH KEY obj_type = is_object-obj_type obj_name = is_object-obj_name
                 text_id = iv_text_id text_key = iv_text_key langu = is_object-master_lang.
      IF sy-subrc = 0 AND ls_master-length > 0.
        lv_limit = ls_master-length.
      ENDIF.
    ENDIF.

    "Collect the block first so the filter attribute can include the texts.
    DATA lv_body TYPE string.
    DATA(lv_saved) = gv_out.
    CLEAR gv_out.

    add( '<div class="th"><b>' && esc( zzwn00224895_ai_texts_api=>kind_label( iv_obj_type = is_object-obj_type iv_text_id = iv_text_id ) )
      && '</b><span>' && esc( iv_text_id ) && ' ' && esc( iv_text_key ) && '</span>' ).
    IF iv_text_id = zzwn00224895_ai_texts_api=>gc_id_symbol AND is_object-obj_type = zzwn00224895_ai_texts_api=>gc_obj_prog.
      add( '<span class="len">defined length ' && |{ lv_limit }| && ', max ' && |{ lv_max }| && '</span>' ).
    ELSE.
      add( '<span class="len">max ' && |{ lv_max }| && '</span>' ).
    ENDIF.
    add( '</div>' ).

    add( '<div class="orig">' ).
    DATA lv_visible TYPE i.
    LOOP AT is_view-langs INTO DATA(ls_lang) WHERE visible = abap_true.
      lv_visible = lv_visible + 1.
      READ TABLE is_view-originals INTO DATA(ls_orig)
        WITH KEY obj_type = is_object-obj_type obj_name = is_object-obj_name
                 text_id = iv_text_id text_key = iv_text_key langu = ls_lang-langu.
      IF sy-subrc = 0.
        lv_filter = lv_filter && to_lower( ls_orig-text ) && ` `.
        add( '<span><span class="lg">' && esc( ls_lang-iso ) && '</span> <span class="t">' && esc( ls_orig-text ) && '</span>' ).
        IF ls_orig-ddic_ref = abap_true.
          add( '<span class="len" title="Selection text taken from the Dictionary">DDIC</span>' ).
        ENDIF.
        add( len_html( iv_len = strlen( ls_orig-text ) iv_limit = lv_limit iv_hard = lv_max ) && '</span>' ).
      ELSE.
        add( '<span><span class="lg off">' && esc( ls_lang-iso ) && '</span> <span class="len">not available</span></span>' ).
      ENDIF.
    ENDLOOP.
    IF lv_visible = 0.
      add( '<span class="len">original texts hidden - choose languages above</span>' ).
    ENDIF.
    add( '</div>' ).

    LOOP AT is_view-suggestions INTO DATA(ls_sug)
         WHERE obj_type = is_object-obj_type AND obj_name = is_object-obj_name
           AND text_id = iv_text_id AND text_key = iv_text_key.
      lv_filter = lv_filter && to_lower( ls_sug-new_text ) && ` ` && to_lower( ls_sug-iso ) && ` #` && |{ ls_sug-id }| && ` `.
      suggestion( ls_sug ).
    ENDLOOP.

    lv_body = gv_out.
    gv_out = lv_saved.
    add( '<div class="txt" data-k="' && esc( lv_filter ) && '">' && lv_body && '</div>' ).
  ENDMETHOD.

  METHOD suggestion.
    DATA(lv_limit) = COND i( WHEN is_sug-new_length > 0 THEN is_sug-new_length ELSE is_sug-max_len ).

    add( '<div class="sug ' && is_sug-status && '" id="s' && |{ is_sug-id }| && '"><div class="sid">#' && |{ is_sug-id }| && '</div>' ).
    add( '<div class="body"><div><span class="lg on">' && esc( is_sug-iso ) && '</span> <span class="act ' && is_sug-action && '">'
      && esc( is_sug-action ) && '</span> ' ).
    IF is_sug-action = zzwn00224895_ai_texts_api=>gc_act_delete.
      add( '<span class="new del">' && esc( is_sug-old_text ) && '</span>' ).
    ELSE.
      add( '<span class="new">' && esc( is_sug-new_text ) && '</span>'
        && len_html( iv_len = strlen( is_sug-new_text ) iv_limit = lv_limit iv_hard = is_sug-max_len ) ).
      IF is_sug-new_length > 0 AND is_sug-new_length <> is_sug-old_length AND is_sug-old_length > 0.
        add( '<span class="len" title="The defined length of the text symbol is changed">defined length '
          && |{ is_sug-old_length } &rarr; { is_sug-new_length }| && '</span>' ).
      ENDIF.
    ENDIF.
    add( '</div>' ).

    IF is_sug-action = zzwn00224895_ai_texts_api=>gc_act_change.
      add( '<div class="was">was: ' && esc( is_sug-old_text ) && '</div>' ).
    ENDIF.
    IF is_sug-rationale IS NOT INITIAL.
      add( '<div class="rat">' && esc( is_sug-rationale ) && '</div>' ).
    ENDIF.

    DATA(lv_status) = zzwn00224895_ai_texts_api=>status_label( is_sug-status ).
    DATA(lv_cls) = 'st'.
    CASE is_sug-status.
      WHEN zzwn00224895_ai_texts_api=>gc_st_applied.
        lv_cls = 'st ok'.
        IF is_sug-request IS NOT INITIAL.
          lv_status = lv_status && | (request { is_sug-request })|.
        ENDIF.
      WHEN zzwn00224895_ai_texts_api=>gc_st_failed.
        lv_cls = 'st err'.
        lv_status = lv_status && |: { is_sug-error }|.
      WHEN zzwn00224895_ai_texts_api=>gc_st_superseded.
        lv_status = lv_status && | by #{ is_sug-replaced_by }|.
    ENDCASE.
    IF is_sug-comment IS NOT INITIAL.
      lv_status = lv_status && | - "{ is_sug-comment }"|.
    ENDIF.
    IF is_sug-replaces_id > 0.
      lv_status = lv_status && | (replaces #{ is_sug-replaces_id })|.
    ENDIF.
    add( '<div class="' && lv_cls && '">' && esc( lv_status ) && '</div>' ).

    buttons( is_sug ).
    add( '</div></div>' ).
  ENDMETHOD.

  METHOD buttons.
    DATA(lv_id) = |{ is_sug-id }|.
    add( '<div class="acts">' ).
    CASE is_sug-status.
      WHEN zzwn00224895_ai_texts_api=>gc_st_pending.
        add( link( iv_action = 'ACCEPT?id=' && lv_id iv_label = 'Accept' iv_class = 'ok'
                   iv_title = 'Accept; write later with "Apply accepted"' ) ).
        add( link( iv_action = 'APPLY?id=' && lv_id iv_label = 'Accept &amp; apply' iv_class = 'go'
                   iv_title = 'Accept and write this text to the system now' ) ).
        add( link( iv_action = 'RETRY?id=' && lv_id iv_label = '&#8635; Retry' iv_class = 'ask'
                   iv_title = 'Ask the AI for a different suggestion for this text' ) ).
        comment_form( iv_action = 'REQCHG' iv_id = is_sug-id iv_label = 'Request changes' iv_class = 'ask'
                      iv_hint = 'What should the AI change?' iv_submit = 'Send to AI' ).
        comment_form( iv_action = 'DENY' iv_id = is_sug-id iv_label = 'Deny with reason' iv_class = 'no'
                      iv_hint = 'Why is this suggestion not acceptable? (the AI is informed)' iv_submit = 'Deny' ).
        add( link( iv_action = 'REFUSE?id=' && lv_id iv_label = 'Refuse' iv_class = 'no'
                   iv_title = 'Refuse without telling the AI' ) ).
      WHEN zzwn00224895_ai_texts_api=>gc_st_accepted.
        add( link( iv_action = 'APPLY?id=' && lv_id iv_label = 'Apply now' iv_class = 'go' ) ).
        add( link( iv_action = 'UNDO?id=' && lv_id iv_label = 'Undo' iv_class = 'mut' iv_title = 'Back to pending' ) ).
      WHEN zzwn00224895_ai_texts_api=>gc_st_retry OR zzwn00224895_ai_texts_api=>gc_st_changes.
        add( '<span class="len">waiting for a new suggestion from the AI...</span>' ).
        add( link( iv_action = 'UNDO?id=' && lv_id iv_label = 'Cancel request' iv_class = 'mut'
                   iv_title = 'Keep this suggestion pending instead' ) ).
      WHEN zzwn00224895_ai_texts_api=>gc_st_denied OR zzwn00224895_ai_texts_api=>gc_st_refused.
        add( link( iv_action = 'UNDO?id=' && lv_id iv_label = 'Undo' iv_class = 'mut' iv_title = 'Back to pending' ) ).
      WHEN zzwn00224895_ai_texts_api=>gc_st_failed.
        add( link( iv_action = 'APPLY?id=' && lv_id iv_label = 'Apply again' iv_class = 'go' ) ).
        add( link( iv_action = 'UNDO?id=' && lv_id iv_label = 'Undo' iv_class = 'mut' ) ).
      WHEN OTHERS.
        "applied / superseded: nothing to do
    ENDCASE.
    add( '</div>' ).
  ENDMETHOD.

  METHOD comment_form.
    add( '<details class="frm"><summary class="b ' && iv_class && '">' && iv_label && '</summary>' ).
    add( '<form method="post" action="SAPEVENT:' && iv_action && '"><input type="hidden" name="id" value="' && |{ iv_id }| && '">' ).
    add( '<textarea name="comment" rows="2" maxlength="' && |{ gc_max_comment }| && '" placeholder="' && esc( iv_hint ) && '"></textarea>' ).
    add( '<input type="submit" value="' && esc( iv_submit ) && '"></form></details>' ).
  ENDMETHOD.

  METHOD footer.
    add( '<div class="foot">' ).
    add( link( iv_action = 'ACCEPT_ALL' iv_label = 'Accept all pending' iv_class = 'ok' ) ).
    add( link( iv_action = 'APPLY_ACCEPTED' iv_label = 'Apply accepted (' && |{ is_view-cnt_accepted }| && ')' iv_class = 'ok' ) ).
    add( link( iv_action = 'APPLY_ALL' iv_label = 'Import: accept &amp; apply all' iv_class = 'go'
               iv_title = 'Accept every pending suggestion and write all accepted texts to the system' ) ).
    add( '<span class="sp"></span>' ).
    add( link( iv_action = 'CLOSE' iv_label = 'Close review' iv_class = 'no' ) ).
    add( '</div>' ).
  ENDMETHOD.

ENDCLASS.
