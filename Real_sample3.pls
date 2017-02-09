create or replace package real_sample3 is
  --------------------------------------------------------------------------


  --------------------------------------------------------------------------

  gc_package              constant varchar2(30) := 'real_sample3';
  gc_sendoppdragk         constant varchar2(30) := 'sendOppdragK';
  gc_sendstatusk          constant varchar2(30) := 'sendStatusK';
  
  --Return codes
  gc_rc_confirmed         constant number := 1; --OK message confirmed
  gc_rc_duplicate         constant number := 7; --Rejected - duplcate
  gc_rc_error_input       constant number := 8; --Rejected - error in input data
  gc_rc_other_error       constant number := 9; --Rejected - other kind of error
  
  log_status_code_success constant varchar2(10) := 'SUCCESS';
  log_status_code_error   constant varchar2(10) := 'ERROR';
  
  -- This function sets return for sendoppdragK and sendstatusk operations.
  --
  -- Parameters:
  --   p_operation        Should be set either real_sample3.gc_sendoppdragk or
  --                      svc_dbs.oppdragk.gc_sendstatusk.
  --   p_return_code      Should be set either gc_rc_confirmed, gc_rc_duplicate, 
  --                      gc_rc_error_input or gc_rc_other_error of real_sample3 spec.
  --   p_comment_id       If it is provided, then message is taken from 'YNO_DBS_SVT_DECISION_COMMENT'
  --   p_comment_message  It overrides p_comment_id. Custom message.
  ------------------------------------------------------------------------------
  procedure set_return(p_operation       in varchar2,
                       p_return_code     in number, 
                       p_comment_id      in varchar2 := null,
                       p_comment_message in varchar2 := null);
  --------------------------------------------------------------------------
  -- This procedure process sendOppdragK webservice.
  --
  -- Parameters:
  --   p_input_token  Standard input token,
  --   p_request      OOT representing request for sendOppdragK
  --   p_response     OOT representing response from sendOppdragK
  --   p_result       Standard result object type
  procedure sendoppdragk(p_input_token in obj_input_token,
                         p_request     in obj_dbs_send_oppdragk_request,
                         p_response    out nocopy obj_dbs_send_oppdragk_response,
                         p_result      out nocopy obj_result);

  --------------------------------------------------------------------------
  -- This procedure process sendStatusK webservice.
  --
  -- Parameters:
  --   p_input_token  Standard input token,
  --   p_request      OOT representing request for sendStatusK
  --   p_response     OOT representing response from sendStatusK
  --   p_result       Standard result object type
  procedure sendstatusk(p_input_token in obj_input_token,
                        p_request     in obj_dbs_send_statusk_request,
                        p_response    out nocopy obj_dbs_send_statusk_response,
                        p_result      out nocopy obj_result);

end;
/
create or replace package body real_sample3 is
  --------------------------------------------------------------------------
  -- Subject    : DBS Oppdragk service
  -- File       : $Release: @releaseVersion@ $
  --              $Id: real_sample3.pls 71828 2016-11-25 06:44:44Z apr $
  -- Copyright (c) TIA Technology A/S 1998-2015. All rights reserved.
  --------------------------------------------------------------------------
  gw_statusk_response  obj_dbs_send_statusk_response;
  gw_oppdragk_response obj_dbs_send_oppdragk_response;

  ------------------------------------------------------------------------------
  procedure trace_configuration is
    c_program     constant varchar2(50) := 'trace_configuration';
    w_site_pref   tia_preference.arguments%type;
  begin

    w_site_pref := x_site_preference('YNO_DBS_TRACE_CONFIG');
    
    if w_site_pref is null then
      return;
    end if;
  
    if upper(nvl(x_get_var(w_site_pref, 'SET_TRACE'), 'N')) = 'Y' then
      p0000.trace_level := nvl(x_get_var(w_site_pref, 'LEVEL'), 99);
      p0000.trace_type  := nvl(x_get_var(w_site_pref, 'TYPE'), 3);
      p0000.trace_name  := nvl(x_get_var(w_site_pref, 'NAME'), 'SVC_DBS_TRACE_' || to_char(sysdate, 'yyyymmddHHMI'));
    else
      return;
    end if;

  end;
  ------------------------------------------------------------------------------
  procedure dbs_trace(p_trace_text varchar2,
                      p_program    varchar2 default null) is
  
  begin
    z_program(gc_package || '.' || p_program);
    z_trace(p_trace_text);
  end;
  --------------------------------------------------------------------------  
  procedure create_cla_item(p_sop_request    in obj_dbs_send_oppdragk_request,
                            p_cla_subcase_no in cla_subcase.cla_subcase_no%type default null,
                            p_wrkshop_id_no  in name.id_no%type default null,
                            p_cla_item_no    in out cla_item.cla_item_no%type,
                            p_error_code     out number,
                            p_error_message  out varchar2) is
    c_program constant varchar2(32) := 'sendOppdragk';

    w_cla_event_no       cla_item.cla_event_no%type;
    w_estimate           cla_item.estimate%type;
    w_items_changed      varchar2(32000) := ',';
    w_paid_invoice_sum   number := 0;
    w_risk_no            cla_case.risk_no%type;
    w_subrisk_no         cla_case.subrisk_no%type;
    w_name_id_no         cla_case.name_id_no%type;
    w_al_seq_no          agreement_line.agr_line_seq_no%type;
    w_claim_type         varchar2(50);
  
  begin
  
    p5600.clr;
  
    select cla_event_no, name_id_no
    into   w_cla_event_no,
           w_name_id_no
    from   cla_case
    where  cla_case_no = p_sop_request.claim_number;
  
    p5600.cla_item_rec.cla_event_no   := w_cla_event_no;
    p5600.cla_item_rec.cla_case_no    := p_sop_request.claim_number;
    p5600.cla_item_rec.cla_subcase_no := p_cla_subcase_no;
  
    p5600.cla_item_rec.description := substr('DBSK OppdragsK ' || p_sop_request.estimate_number || ' ' || p_sop_request.estimate_version,
                                             1,
                                             2000);
    w_items_changed                := w_items_changed || 'description,';
  
    p5600.cla_item_rec.receiver_id_no := w_name_id_no; 
    w_items_changed                   := w_items_changed || 'receiver_id_no,';
  
    select cc.policy_line_seq_no
    into   w_al_seq_no
    from   cla_case cc
    join   agreement_line al
    on     al.agr_line_seq_no = cc.policy_line_seq_no
    where  cc.cla_case_no = p_sop_request.claim_number;
  
    w_claim_type := bno72.convert_damagetype_id(p_sop_request.damage_type_id);
    w_risk_no    := bno72.uf_72_get_risk_no(c_program, w_claim_type, bno72.claim_item_table_name, w_al_seq_no);
    if w_risk_no is null then
      svc_dbs.create_error_case('NO09', 0, p_sop_request.claim_number, w_claim_type, bno72.claim_item_table_name, w_al_seq_no);
    else
      p5600.cla_item_rec.risk_no := w_risk_no;
    end if;
  
    w_subrisk_no := bno72.uf_72_get_subrisk_no(c_program, w_claim_type, bno72.claim_item_table_name, w_al_seq_no);
    if w_subrisk_no is null then
      svc_dbs.create_error_case('NO10', 0, p_sop_request.claim_number, w_claim_type, bno72.claim_item_table_name, w_al_seq_no);
    else
      p5600.cla_item_rec.subrisk_no := w_subrisk_no;
    end if;
  
    if p_cla_item_no is null then
      p5600.cla_item_rec.status := 'OP';
    end if;
  
    p5600.cla_item_rec.handler := x_site_preference('YNO_DBS_ESTIMATOR');
    w_items_changed            := w_items_changed || 'handler,';
  
    p5600.cla_item_rec.item_type     := 'RE';
    p5600.cla_item_rec.subitem_type  := 'DBSK';
    p5600.cla_item_rec.currency_code := 'NOK';
  
    select object_id,
           object_no,
           object_seq_no
    into   p5600.cla_item_rec.object_id,
           p5600.cla_item_rec.object_no,
           p5600.cla_item_rec.object_seq_no
    from   cla_case
    where  cla_case_no = p_sop_request.claim_number;
  
    w_estimate := bno72.round_decimals(bno72.uf_72_sop_choose_sum(p_sop_request.claim_number, p_cla_subcase_no));
  
    z_program(gc_package || '.' || c_program);
  
    p5600.cla_item_rec.currency_estimate := bno72.round_decimals(w_estimate - w_paid_invoice_sum);
  
    w_items_changed := w_items_changed || 'currency_estimate,';
    w_items_changed := w_items_changed || 'currency_diff,';
    w_items_changed := w_items_changed || 'estimate,';
    w_items_changed := w_items_changed || 'diff,';
  
    bno72.uf_72_oppdragk_fill_cla_item(p_sop_request => p_sop_request, p_items_changed => w_items_changed);
  
    select cc.name_id_no
    into   p5600.cla_item_rec.receiver_id_no
    from   cla_case cc
    where  cla_case_no = p_sop_request.claim_number;
  
    if p_cla_item_no is not null then
      w_items_changed              := w_items_changed || 'seq_no,';
      p5600.cla_item_items_changed := w_items_changed;
    end if;
    p5600.create_claim_item(p_cla_item_no);
    p_cla_item_no := p5600.cla_item_rec.cla_item_no;
    
  exception
  when others then
    --set unexpected error for log
    p_error_code := null;
    p_error_message := substr(sqlerrm, 1, 1000);
    dbs_trace(p_error_message, c_program);
    --set return "Unexpected error"
    set_return(p_operation => gc_sendstatusk, 
               p_return_code => gc_rc_other_error, 
               p_comment_id => 90); 
  end create_cla_item;

  ------------------------------------------------------------------------------
  procedure get_varchar_val(p_seq_no      in number,
                            p_ws_name     in varchar2,
                            p_ws_method   in varchar2,
                            p_ws_flow     in varchar2,
                            p_ws_tag_name varchar2,
                            p_value       in out varchar2) is
  
    w_is_configurable    varchar2(1);
    w_tia_table_name     varchar2(2000);
    w_tia_column_name    varchar2(2000);
    w_add_condition      varchar2(32000);
    w_user_function      varchar2(1);
    w_user_function_name varchar2(2000);
    w_query              varchar2(4000);
    w_select             varchar2(1000);
    w_from               varchar2(1000);
    w_where              varchar2(1000);
    c_cursor             sys_refcursor;
  begin
    bno71.get_mapping_details(p_ws_name,
                              p_ws_method,
                              p_ws_flow,
                              p_ws_tag_name,
                              w_is_configurable,
                              w_tia_table_name,
                              w_tia_column_name,
                              w_add_condition,
                              w_user_function,
                              w_user_function_name);
  
    w_select := 'select item.' || w_tia_column_name;
    w_from   := ' from ' || w_tia_table_name || ' item';
    w_where  := ' where item.seq_no = :p_0 ';
    w_query  := w_select || w_from || w_where;
  
    open c_cursor for w_query
      using p_seq_no;
    fetch c_cursor
      into p_value;
    close c_cursor;
  end get_varchar_val;
  ------------------------------------------------------------------------------
  procedure set_return(p_operation       in varchar2,
                       p_return_code     in number, 
                       p_comment_id      in varchar2 := null,
                       p_comment_message in varchar2 := null) is
    c_program     constant varchar2(50)  := 'set_return';
    w_comment_message  varchar2(200); 
  begin
    --p_comment_message if not null overrides p_comment_id
    if p_comment_id is not null then 
      w_comment_message := x_reference2('YNO_DBS_SVT_DECISION_COMMENT', p_comment_id, 'DESC');
    elsif p_comment_message is not null then
      w_comment_message := p_comment_message;
    elsif p_return_code = gc_rc_other_error then
      --if no message and return code 9 then set "Unexpected error"
      w_comment_message := x_reference2('YNO_DBS_SVT_DECISION_COMMENT', 90, 'DESC');
    end if;
  
    if p_operation = gc_sendstatusk then
      gw_statusk_response.return_code := p_return_code;
      gw_statusk_response.return_text := w_comment_message;
      dbs_trace(gw_statusk_response.return_code ||' - '|| gw_statusk_response.return_text, c_program);
    elsif p_operation = gc_sendoppdragk then
      gw_oppdragk_response.return_code := p_return_code;
      gw_oppdragk_response.return_text := w_comment_message;
      dbs_trace(gw_oppdragk_response.return_code ||' - '|| gw_oppdragk_response.return_text, c_program);
    end if;
    
  end set_return;  
  ------------------------------------------------------------------------------
  procedure create_payment_item(p_request in obj_dbs_send_statusk_request, 
                                p_error_code out number, 
                                p_error_message out varchar2) is
    c_program             constant varchar2(20) := 'create_payment_item';
    w_amount              number;
    w_total_amount        number;
    w_diff                number;
    w_re_amt              number;
    w_bank_account        varchar2(40);
    w_means_pay_no        number;
    w_item_type_list      svc_dbs.item_type;
    w_currency_amt_list   svc_dbs.currency_amt_type;
    w_seq_no_list         svc_dbs.seq_no_type;
    w_currency_code_list  svc_dbs.currency_code_type;
    w_rec_id_no_list      svc_dbs.receiver_id_no_type;
    w_cla_item            cla_item%rowtype;
    w_query               varchar2(4000);
    w_select              varchar2(1000);
    w_from                varchar2(1000);
    w_where               varchar2(1000);
    c_cursor              sys_refcursor;
    w_input_token         obj_input_token;
    w_claim_acc_item      obj_claim_acc_item;
    w_result              obj_result;
    
    cursor c_means_pay_no(p_name_id_no     number,
                          p_payment_method varchar2,
                          p_bank_acc_no    varchar2) is
      select means_pay_no
      from   acc_payment_details
      where  name_id_no = p_name_id_no
      and    payment_method = p_payment_method
      and    bank_account_no = p_bank_acc_no;
      
    -- make subitem_type configurable for deduction and excess
    cursor c_claim_items(p_cla_case_no number) is
      select cla_item_no,
             currency_estimate,
             item_type
      from   cla_item
      where  newest = 'Y'
      and    ((item_type = 'EX' and subitem_type = x_site_preference('YNO_DBS_EX_SUBITEM_TYPE')) or
            (item_type = 'EX' and subitem_type = x_site_preference('YNO_DBS_DE_SUBITEM_TYPE')) or
            (item_type = 'RE' and subitem_type = 'DBS'))
      and    status in ('OP', 'NO', 'RO')
      and    cla_case_no = p_cla_case_no;
  begin
       
    -- checking if claim item exists
    w_select := 'select *';
    w_from   := ' from cla_item cla_item';
    w_where  := ' where cla_item.cla_case_no = :v_p_cla_case_no';
    w_where  := w_where || ' and cla_item.newest = :v_param2';
    w_where  := w_where || ' and cla_item.item_type = :v_param3';
    w_where  := w_where || ' and cla_item.subitem_type = :v_param4';
    w_where  := w_where || ' and cla_item.status in(''OP'',''NO'',''RO'')';
    w_query  := w_select || w_from || w_where;
  
    open c_cursor for w_query
      using p_request.claim_number_dbs, 'Y', 'RE', 'DBSK';
    fetch c_cursor
      into w_cla_item;
    close c_cursor;
  
    if w_cla_item.cla_case_no is null then
      --Set error code
      p_error_code := 8;
      p_error_message := x_reference2('YNO_DBS_ERROR_CODE', p_error_code, 'desc');
      --Set return for response
      set_return(p_operation => gc_sendstatusk,
                 p_return_code => gc_rc_other_error,
                 p_comment_id => 10);
      return;
    end if;
    
    -- Check for locked claim case
    if svc_dbs.check_locked_case(p_request.claim_number_dbs) = 0 then
      --Set error code
      p_error_code := 15;
      p_error_message := x_reference2('YNO_DBS_ERROR_CODE', p_error_code, 'desc');
      --Set return for response
      set_return(p_operation => gc_sendstatusk,
                 p_return_code => gc_rc_other_error,
                 p_comment_id => 70);
      return;
    end if;
    
   
    w_amount := svc_dbs.round_decimals(bno72.uf_72_statusk_calc_comp_amt(p_request));
  
    -- check if invoice amount <= RE-EX
    w_total_amount := 0;
  
    -- make subitem_type configurable for deduction and excess
    w_select := 'select cla_item.item_type, cla_item.currency_estimate,
                       cla_item.currency_code, cla_item.seq_no, cla_item.receiver_id_no';
    w_from   := ' from cla_item cla_item';
    w_where  := ' where cla_item.cla_case_no = ' || p_request.claim_number_dbs;
    w_where  := w_where || ' and cla_item.newest = ''Y''';
    w_where  := w_where ||
                ' and ((cla_item.item_type = ''RE'' and cla_item.subitem_type = ''DBSK'') or (cla_item.item_type = ''EX'' and cla_item.subitem_type = x_site_preference(''YNO_DBS_EX_SUBITEM_TYPE'')) or (cla_item.item_type = ''EX'' and cla_item.subitem_type = x_site_preference(''YNO_DBS_DE_SUBITEM_TYPE'')))';
    w_where  := w_where || ' and cla_item.status in(''OP'',''NO'',''RO'')';
    w_where  := w_where || ' and cla_item.currency_estimate > 0';
    w_query  := w_select || w_from || w_where;
  
    execute immediate w_query bulk collect
      into w_item_type_list, w_currency_amt_list, w_currency_code_list, w_seq_no_list, w_rec_id_no_list;
  
    w_claim_acc_item                     := obj_claim_acc_item();
    w_claim_acc_item.claim_payment_items := tab_claim_payment_item();
  
    --checking total amount
    for elem in 1 .. w_item_type_list.count
    loop
      if w_item_type_list(elem) = 'RE' then
        w_total_amount := w_total_amount + w_currency_amt_list(elem);
      elsif w_item_type_list(elem) = 'EX' then
        w_total_amount := w_total_amount - w_currency_amt_list(elem);
      end if;
    end loop;
    w_diff := w_total_amount - w_amount;
  
    for elem in 1 .. w_item_type_list.count
    loop
      --preparing data for automatic payment
      if w_item_type_list(elem) = 'RE' or
         w_item_type_list(elem) = 'EX' then
        w_claim_acc_item.claim_payment_items.extend;
        w_claim_acc_item.claim_payment_items(elem) := obj_claim_payment_item();
        w_claim_acc_item.claim_payment_items(elem).cla_item_seq_no := w_seq_no_list(elem);
        w_claim_acc_item.claim_payment_items(elem).currency_amount := w_currency_amt_list(elem);
        w_claim_acc_item.claim_payment_items(elem).currency_code := w_currency_code_list(elem);
        w_claim_acc_item.claim_payment_items(elem).payment_type := bno72.uf_72_sfg_get_payment_type(p_request.claim_number_dbs,
                                                                                                    w_seq_no_list(elem));
      end if;
      if w_item_type_list(elem) = 'RE' then
        w_claim_acc_item.receiver_id_no := w_rec_id_no_list(elem);
        w_claim_acc_item.currency_code  := w_currency_code_list(elem);
        if w_diff > 0 then
          w_re_amt := w_currency_amt_list(elem);
          if w_re_amt > w_diff then
            w_claim_acc_item.claim_payment_items(elem).currency_amount := w_re_amt - w_diff;
            w_diff := 0;
          else
            w_claim_acc_item.claim_payment_items(elem).currency_amount := 0;
            w_diff := w_diff - w_re_amt;
          end if;
        end if;
      end if;
    end loop;
    -----------------------------------------------------------------------------------
    if svc_dbs.round_decimals(w_amount) > svc_dbs.round_decimals(w_total_amount) then
      if bno72.uf_72_pre_create_case(p_request.claim_number_dbs, w_total_amount, w_amount) = 0 then
        svc_dbs.create_error_case('NO07', 0, p_request.claim_number_dbs, w_amount, w_total_amount);
      end if;
      --Set error code
      p_error_code := '12';
      p_error_message := x_reference2('YNO_DBS_ERROR_CODE', p_error_code, 'desc');
      --Set return for response
      set_return(p_operation => gc_sendstatusk,
                 p_return_code => gc_rc_other_error,
                 p_comment_message => p_error_message);
    else
       -- acc_payment_details for payment
      open c_means_pay_no(w_claim_acc_item.receiver_id_no, w_claim_acc_item.payment_method, w_bank_account);
      fetch c_means_pay_no
        into w_means_pay_no;
      if c_means_pay_no%notfound then
        t6064.clr;
        bno72.uf_72_create_paym_details(w_bank_account, w_claim_acc_item, t6064.rec);
        t6064.ins;
        w_means_pay_no := t6064.rec.means_pay_no;
      end if;
      close c_means_pay_no;
      w_claim_acc_item.means_pay_no := w_means_pay_no;
      svc_claim_payment.createclaimpayment(w_input_token, w_claim_acc_item, w_result);
      
      if w_result.doeserrorexist
      then
        for elem in 1 .. w_result.messages.count
        loop
          p_error_message := p_error_message || w_result.messages(elem)
                            .message_text || ',';
        end loop;
        p_error_code := '11';
        
        svc_dbs.create_error_case('NO36'
                     ,2
                     ,p_request.claim_number_dbs
                     ,p_error_message);
         
        set_return(p_operation => gc_sendoppdragk, 
                   p_return_code => gc_rc_confirmed);             
        
      end if;
    
    end if;

  exception
    when others then
      --set unexpected error for log
      p_error_code := null;
      p_error_message := substr(sqlerrm, 1, 1000);
      dbs_trace(p_error_message, c_program);
      --set return "Unexpected error"
      set_return(p_operation => gc_sendstatusk, 
                 p_return_code => gc_rc_other_error, 
                 p_comment_id => 90);  
  end create_payment_item;
  ------------------------------------------------------------------------------
  function  check_duplicate_estimate(p_request in obj_dbs_send_oppdragk_request) return boolean is 
    c_program    constant varchar2(50) := 'check_duplicate_estimate';
    
    w_prev_estimate_number  varchar2(8);
    w_prev_estimate_version number;
    w_curr_estimate_number  varchar2(8);
    w_curr_estimate_version number;
    w_is_configurable       yno_dbs_mapping.is_configurable%type;
    w_tia_table_name        yno_dbs_mapping.tia_table_name%type;
    w_tia_column_name_n     yno_dbs_mapping.tia_column_name%type;
    w_tia_column_name_v     yno_dbs_mapping.tia_column_name%type;
    w_user_function         yno_dbs_mapping.user_function%type;
    w_user_function_name    yno_dbs_mapping.user_function_name%type;    
    w_add_condition         varchar2(100);
    w_cursor                sys_refcursor;
    w_query                varchar2(200);
    
  begin
  
   --Get current estimate number:
   --it is either the one in request or from user function if it is configurable in it

    
   if (w_user_function = 'Y') then
        execute immediate '
      begin
        :v_curr_estimate_number := ' || w_user_function_name ||
                                   '(:p_request);
      end;
    '
          using out w_curr_estimate_number, in p_request;
   else
     w_curr_estimate_number := p_request.estimate_number;
   end if; 
   
   --Get current estimate version:
   --it is either the one in request or from user function if it is configurable in it
   bno71.get_mapping_details('OppdragK',
                             'SendOppdragK',
                             'RQ',
                             'EstimateVersion',
                             w_is_configurable,
                             w_tia_table_name,
                             w_tia_column_name_v,
                             w_add_condition,
                             w_user_function,
                             w_user_function_name);
    
   if (w_user_function = 'Y') then
        execute immediate '
      begin
        :w_curr_estimate_version := ' || w_user_function_name ||
                                    '(:p_request);
      end;
    '
          using out w_curr_estimate_version, in p_request;
   else
     w_curr_estimate_version := p_request.estimate_version;
   end if; 
   
   dbs_trace('w_curr_estimate_number: ' || w_curr_estimate_number ||
             ', w_curr_estimate_version: ' || w_curr_estimate_version, c_program);
             
   --Build query to get previous estimate number and version (if exists)
   w_query := 'select ' || w_tia_column_name_n || ', ' || w_tia_column_name_v ||
               '  from ' || w_tia_table_name ||
               ' where cla_case_no = :cla_case_no
                   and newest = ''Y''
                   and item_type = ''RE''
                   and subitem_type = ''DBSK''';   
                   

   if w_prev_estimate_number is not null and w_prev_estimate_version is not null then 
     if w_prev_estimate_number = w_curr_estimate_number and 
       w_prev_estimate_version >= w_curr_estimate_version then 
         return false;
       end if;
   end if;    
   
   return true;
    
  end check_duplicate_estimate;
  ------------------------------------------------------------------------------
  function does_car_exist(p_licence_number in varchar2) return boolean is
    c_program     constant varchar2(50)  := 'does_car_exist';  
    w_item_count  number;
  
    cursor c_get_objects_count(cp_object_id varchar2) is 
      select count(o.object_no)
      from   object o
      where  o.object_id = cp_object_id;
  begin
    
    dbs_trace('Licence Number: ' || p_licence_number);
    open c_get_objects_count(p_licence_number);
      fetch c_get_objects_count
        into w_item_count;
    close c_get_objects_count;
    
    if w_item_count < 1 then 
      dbs_trace('Car does not exist');
      return false;
    else
      dbs_trace('Car exists');
      return true;
    end if;
    
  end does_car_exist;
  ------------------------------------------------------------------------------
  procedure sendoppdragk(p_input_token in obj_input_token,
                         p_request     in obj_dbs_send_oppdragk_request,
                         p_response    out nocopy obj_dbs_send_oppdragk_response,
                         p_result      out nocopy obj_result) is
  
    c_operation_number constant varchar2(3) := '010';
    c_msg_id_other     constant varchar2(17) := 'DBS-OPK-010-99999';
    c_program          constant varchar2(20) := 'sendoppdragk';
    
    w_input_token        obj_input_token;
    w_item_count         number;
    w_logging_req_seq_no number;
    w_return_code        number;
    w_comment_id         varchar2(3);
    w_cla_item_no        number;
    
    w_error_code         number;
    w_error_message      varchar2(500);
  
    --Exceptions
    e_claim_number_not_found exception;
    e_car_not_found          exception;
    e_duplicate_req          exception;
  
    cursor c_get_item_count(cp_cla_case_no number) is
      select count(cc.cla_case_no)
      from   cla_case cc
      where  cc.cla_case_no = cp_cla_case_no;
  
  begin

    gw_oppdragk_response := obj_dbs_send_oppdragk_response();
  
    trace_configuration;
    dbs_trace('Start sendOppdragK');
  
    if p_input_token is null then
      w_input_token          := obj_input_token();
      w_input_token.user_id  := x_site_preference('YNO_DBS_CLAIM_USER_ID');
      w_input_token.trace_yn := 'Y';
    else
      w_input_token := p_input_token;
    end if;
  
    utl_foundation.init_operation(p_input_token => w_input_token, 
                                  p_service => gc_package, 
                                  p_operation => gc_sendoppdragk);
    
    bno74.log_sendoppdragk_request(p_sop_request => p_request, 
                                   p_request_seq_no => w_logging_req_seq_no);
   
    if not check_duplicate_estimate(p_request) then
      raise e_duplicate_req;
    end if;
    
    --Check if claim exists
    open c_get_item_count(p_request.claim_number);
    fetch c_get_item_count
      into w_item_count;
    close c_get_item_count;
    
    if w_item_count < 1 then
      raise e_claim_number_not_found;
    end if;
    
    if p_request.license_number is null or not does_car_exist(p_request.license_number) then
      raise e_car_not_found;
    end if;
  
    bno72.uf_72_oppdragk_before_step(p_request, w_cla_item_no);
    if p_request.message_code = 340 then
      create_cla_item(p_sop_request => p_request, 
                      p_cla_item_no => w_cla_item_no, 
                      p_error_code => w_error_code, 
                      p_error_message => w_error_message);
    end if;
    bno72.uf_72_oppdragk_after_step(p_request, w_cla_item_no);
    
    --if everything went well & return code was not filled with value
    --greater than 1, we return confirmation
    if gw_oppdragk_response.return_code is null then
      gw_oppdragk_response.return_code := gc_rc_confirmed;
    end if; 
  
    p_response := gw_oppdragk_response;
    
    utl_foundation.close_operation(p_input_token    => w_input_token,
                                   p_service        => gc_package,
                                   p_operation      => gc_sendoppdragk,
                                   p_svc_error_code => c_msg_id_other,
                                   p_result         => p_result);    
  
    if w_error_code is null then
      bno74.log_sendoppdragk_response(p_request_seq_no  => w_logging_req_seq_no,
                                      p_response_status => log_status_code_success,
                                      p_err_msg         => null,
                                      p_sop_response    => p_response);
    else
      bno74.log_sendoppdragk_response(p_request_seq_no  => w_logging_req_seq_no,
                                      p_response_status => log_status_code_error,
                                      p_err_msg         => w_error_message,
                                      p_sop_response    => p_response);
    end if;
  
  exception
    when e_claim_number_not_found then
      --set error for log
      w_error_code := 8;
      w_error_message := x_reference2('YNO_DBS_ERROR_CODE', w_error_code, 'DESC');
      dbs_trace(w_error_message, c_program);
      
      --set return "Given claim case_no does not exist"
      set_return(p_operation => gc_sendoppdragk,
                 p_return_code => gc_rc_other_error, 
                 p_comment_id => 10);  
                      
      utl_foundation.close_operation(p_input_token    => w_input_token,
                                     p_service        => gc_package,
                                     p_operation      => gc_sendoppdragk,
                                     p_svc_error_code => c_msg_id_other,
                                     p_result         => p_result);                        
                 
      goto cleanup;
    when e_car_not_found then
      --set error for log
      w_error_code := 17;
      w_error_message := x_reference2('YNO_DBS_ERROR_CODE', w_error_code, 'DESC');
      dbs_trace(w_error_message, c_program);
      
      --set return "License Number is unknown."
      set_return(p_operation => gc_sendoppdragk,
                 p_return_code => gc_rc_other_error, 
                 p_comment_id => 63);  
                      
      utl_foundation.close_operation(p_input_token    => w_input_token,
                                     p_service        => gc_package,
                                     p_operation      => gc_sendoppdragk,
                                     p_svc_error_code => c_msg_id_other,
                                     p_result         => p_result);                        
                 
      goto cleanup;  
    when e_duplicate_req then 
      --set unexpected error for log
      w_error_code := 22;
      w_error_message := x_reference2('YNO_DBS_SVT_DECISION_COMMENT', w_error_code, 'DESC');
      dbs_trace(w_error_message, c_program);
      --set return "Estimate number and estimate version is already registered."
      set_return(p_operation => gc_sendoppdragk,
                 p_return_code => gc_rc_duplicate, 
                 p_comment_id => 22);
                 
      utl_foundation.close_operation(p_input_token    => w_input_token,
                                     p_service        => gc_package,
                                     p_operation      => gc_sendoppdragk,
                                     p_svc_error_code => c_msg_id_other,
                                     p_result         => p_result);  
      
      goto cleanup;                                          
    when others then
      --set unexpected error for log
      w_error_code := null;
      w_error_message := substr(sqlerrm, 1, 1000);
      dbs_trace(w_error_message, c_program);
      --set return "Unexpected error"
      set_return(p_operation => gc_sendoppdragk, 
                 p_return_code => gc_rc_other_error, 
                 p_comment_id => 90);
      
      utl_foundation.handle_service_exception(p_input_token    => w_input_token,
                                              p_service        => gc_package,
                                              p_operation      => gc_sendoppdragk,
                                              p_svc_error_code => c_msg_id_other,
                                              p_result         => p_result);
      goto cleanup;
      
      <<cleanup>>
      
      --set response and log 
      p_response := gw_oppdragk_response;
      
      bno74.log_sendoppdragk_response(p_request_seq_no  => w_logging_req_seq_no,
                                      p_response_status => log_status_code_error,
                                      p_err_msg         => w_error_message,
                                      p_sop_response    => p_response);     
    
  end sendoppdragk;
  ------------------------------------------------------------------------------
  procedure sendstatusk(p_input_token in obj_input_token,
                        p_request     in obj_dbs_send_statusk_request,
                        p_response    out nocopy obj_dbs_send_statusk_response,
                        p_result      out nocopy obj_result) is
                        
    c_operation_number constant varchar2(3) := '020';
    c_msg_id_other     constant varchar2(17) := 'DBS-OPK-020-99999';
    c_program          constant varchar2(20) := 'sendstatusk';
    
    w_input_token obj_input_token;
    w_item_count  number;
    w_kid         varchar2(25);
    w_comment_id  varchar2(3);
    w_logging_req_seq_no number;
    
    w_error_code         number;
    w_error_message      varchar2(500);
    
    --Exceptions
    e_claim_number_not_found exception;
    e_car_not_found          exception;
    
    cursor c_get_item_count(cp_cla_case_no number) is
      select count(cc.cla_case_no)
      from   cla_case cc
      where  cc.cla_case_no = cp_cla_case_no;
      
  begin
    
    gw_statusk_response := obj_dbs_send_statusk_response();
   
    trace_configuration;
    dbs_trace('Start sendOppdragK');
  
    if p_input_token is null then
      w_input_token          := obj_input_token();
      w_input_token.user_id  := x_site_preference('YNO_DBS_CLAIM_USER_ID');
      w_input_token.trace_yn := 'Y';
    else
      w_input_token := p_input_token;
    end if;
  
    utl_foundation.init_operation(p_input_token => w_input_token, 
                                  p_service => gc_package, 
                                  p_operation => gc_sendstatusk);
    
    bno74.log_sendstatusk_request(p_sop_request => p_request, 
                                  p_request_seq_no => w_logging_req_seq_no);
   
    open c_get_item_count(p_request.claim_number_dbs);
    fetch c_get_item_count
      into w_item_count;
    close c_get_item_count;
    
    --Check if claim exists
    if w_item_count < 1 then
      raise e_claim_number_not_found;
    end if;
  
    if p_request.licence_number is not null then     
      --Check if vehicle exists
      if not does_car_exist(p_request.licence_number) then
        raise e_car_not_found;
      end if;
    end if;
    
    bno72.uf_72_statusk_before_step(p_request);
    if p_request.message_code = 360 then
      create_payment_item(p_request => p_request,
                          p_error_code => w_error_code,
                          p_error_message => w_error_message);
    elsif p_request.message_code = 370 then
      bno72.uf_72_vehicle_sold(p_request, w_kid); --wkid as in????
    end if;
    bno72.uf_72_statusk_after_step(p_request);
    
    --if everything went well & return code was not filled with value
    --greater than 1, we return confirmation
    if gw_statusk_response.return_code is null then
      gw_statusk_response.return_code := gc_rc_confirmed;
    end if; 
    
    p_response := gw_statusk_response;
    
    utl_foundation.close_operation(p_input_token    => w_input_token,
                                   p_service        => gc_package,
                                   p_operation      => gc_sendstatusk,
                                   p_svc_error_code => c_msg_id_other,
                                   p_result         => p_result);   
    
    if w_error_code is null then
      bno74.log_sendstatusk_response(p_request_seq_no  => w_logging_req_seq_no,
                                     p_response_status => log_status_code_success,
                                     p_err_msg         => null,
                                     p_sop_response    => p_response);
    else
      bno74.log_sendstatusk_response(p_request_seq_no  => w_logging_req_seq_no,
                                     p_response_status => log_status_code_error,
                                     p_err_msg         => w_error_message,
                                     p_sop_response    => p_response);
    end if;
    
  exception
    when e_claim_number_not_found then
      --set error for log
      w_error_code := 8;
      w_error_message := x_reference2('YNO_DBS_ERROR_CODE', w_error_code, 'DESC');
      dbs_trace(w_error_message, c_program);
      
      --set return "Given claim case_no does not exist"
      set_return(p_operation => gc_sendstatusk,
                 p_return_code => gc_rc_other_error, 
                 p_comment_id => 10);  
                      
      utl_foundation.close_operation(p_input_token    => w_input_token,
                                     p_service        => gc_package,
                                     p_operation      => gc_sendstatusk,
                                     p_svc_error_code => c_msg_id_other,
                                     p_result         => p_result);                        
                 
      goto cleanup;
    when e_car_not_found then
      --set error for log
      w_error_code := 17;
      w_error_message := x_reference2('YNO_DBS_ERROR_CODE', w_error_code, 'DESC');
      dbs_trace(w_error_message, c_program);
      
      --set return "License Number is unknown."
      set_return(p_operation => gc_sendstatusk,
                 p_return_code => gc_rc_other_error, 
                 p_comment_id => 63);  
                      
      utl_foundation.close_operation(p_input_token    => w_input_token,
                                     p_service        => gc_package,
                                     p_operation      => gc_sendstatusk,
                                     p_svc_error_code => c_msg_id_other,
                                     p_result         => p_result);                        
                 
      goto cleanup;
    when others then
      --set unexpected error for log
      w_error_code := null;
      w_error_message := substr(sqlerrm, 1, 1000);
      dbs_trace(w_error_message, c_program);
      --set return "Unexpected error"
      set_return(p_operation => gc_sendstatusk, 
                 p_return_code => gc_rc_other_error, 
                 p_comment_id => 90);
      
      utl_foundation.handle_service_exception(p_input_token    => w_input_token,
                                              p_service        => gc_package,
                                              p_operation      => gc_sendstatusk,
                                              p_svc_error_code => c_msg_id_other,
                                              p_result         => p_result);
      goto cleanup;
      
      <<cleanup>>
      
      --set response and log 
      p_response := gw_statusk_response;
      
      bno74.log_sendstatusk_response(p_request_seq_no  => w_logging_req_seq_no,
                                      p_response_status => log_status_code_error,
                                      p_err_msg         => w_error_message,
                                      p_sop_response    => p_response);
                         
  end sendstatusk;

end;
/
