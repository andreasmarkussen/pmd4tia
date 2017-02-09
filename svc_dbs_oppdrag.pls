CREATE OR REPLACE package svc_dbs_oppdrag is
  --------------------------------------------------------------------------
  -- Subject    : DBS Oppdrag service
  -- File       : $Release: @releaseVersion@ $
  --              $Id: svc_dbs_oppdrag.pls 72122 2016-12-01 15:04:50Z apr $
  -- Copyright (c) TIA Technology A/S 1998-2015. All rights reserved.
  --------------------------------------------------------------------------

  gc_package              constant varchar2(30) := 'svc_dbs_oppdrag';
  log_status_code_success constant varchar2(10) := 'SUCCESS';
  log_status_code_error   constant varchar2(10) := 'ERROR';

  --------------------------------------------------------------------------
  -- This procedure process sendOppdrag webservice.
  --
  -- Parameters:
  --   p_input_token  Standard input token,
  --   p_request      OOT representing request for sendOppdrag
  --   p_response     OOT representing response from sendOppdrag
  --   p_result       Standard result object type
  procedure sendoppdrag(p_input_token in obj_input_token
                       ,p_request     in obj_dbs_send_oppdrag_request
                       ,p_response    out nocopy obj_dbs_send_oppdrag_response
                       ,p_result      out nocopy obj_result);

  --------------------------------------------------------------------------
  -- This procedure process sendStatus webservice.
  --
  -- Parameters:
  --   p_input_token  Standard input token,
  --   p_request      OOT representing request for sendStatus
  --   p_response     OOT representing response from sendStatus
  --   p_result       Standard result object type
  procedure sendstatus(p_input_token in obj_input_token
                      ,p_request     in obj_dbs_send_status_request
                      ,p_response    out nocopy obj_dbs_send_status_response
                      ,p_result      out nocopy obj_result);

end;

/


CREATE OR REPLACE package body svc_dbs_oppdrag is
  --------------------------------------------------------------------------
  -- Subject    : DBS Oppdrag service
  -- File       : $Release: @releaseVersion@ $
  --              $Id: svc_dbs_oppdrag.pls 72122 2016-12-01 15:04:50Z apr $
  -- Copyright (c) TIA Technology A/S 1998-2015. All rights reserved.
  --------------------------------------------------------------------------
  procedure set_decision(p_sop_response in out obj_dbs_send_oppdrag_response
                        ,p_decision     in varchar2
                        ,p_comment_id   in varchar2) is
    w_xr_desc varchar2(60);
  begin
   
    w_xr_desc := x_reference2('YNO_DBS_SVT_DECISION_COMMENT'
                             ,p_comment_id
                             ,'DESC');
  
    p_sop_response.return_code := substr(p_decision
                                        ,1
                                        ,1);
    p_sop_response.return_text := w_xr_desc;
  
  end set_decision;

  procedure trace_configuration
  
   is
    w_site_pref tia_preference.arguments%type;
   
  begin
    w_site_pref := x_site_preference('YNO_DBS_TRACE_CONFIG');
    if w_site_pref is null
    then
      return;
    end if;
  
    if upper(nvl(x_get_var(w_site_pref
                          ,'SET_TRACE')
                ,'N')) = 'Y'
    then
      p0000.trace_level := nvl(x_get_var(w_site_pref
                                        ,'LEVEL')
                              ,99);
      p0000.trace_type  := nvl(x_get_var(w_site_pref
                                        ,'TYPE')
                              ,3);
      p0000.trace_name  := nvl(x_get_var(w_site_pref
                                        ,'NAME')
                              ,'SVC_DBS_TRACE_' ||
                               to_char(sysdate
                                      ,'yyyymmddHHMI'));
    else
      return;
    end if;
  
  end;

  ------------------------------------------------------------------------------
  procedure dbs_trace(p_trace_text varchar2
                     ,p_program    varchar2) is
  
  begin
    z_program(gc_package || '.' || p_program);
    z_trace(p_trace_text);
  end;

  ------------------------------------------------------------------------------
  function translate_text(text      varchar2
                         ,user_lang varchar2) return varchar2
  
   is
    msg  varchar2(500); -- resulting message
    arg  varchar2(500) := null; -- holds (remaning) arguments for substitution
    var  varchar2(500); -- holds one argument
    i    number(3);
    p    number(2) := 0; -- argument number
    lang varchar2(3);
  
    cursor std_msg(p_lang varchar2) is
      select description
        from xla_reference
       where table_name = 'STANDARD_MESSAGE'
         and code = substr(msg
                          ,2
                          ,4)
         and language = p_lang;
  
  begin
    lang := user_lang;
    <<again>>
    msg := text;
    i   := instr(msg
                ,';');
    if i > 0
    then
      arg := substr(msg
                   ,i + 1) || ';';
      msg := substr(msg
                   ,1
                   ,i - 1);
    end if;
    if substr(msg
             ,1
             ,1) = '#'
    then
      open std_msg(lang);
      fetch std_msg
        into msg;
      if std_msg%notfound
      then
        null;
      end if;
      close std_msg;
    
      if instr(msg
              ,'<Please Translate>') > 0
      then
        if lang <> 'TIA'
        then
          lang := 'TIA';
          goto again;
        end if;
      end if;
    end if;
    -- substitute variables if any
    if arg is null
    then
      return msg;
    end if;
    loop
      i   := instr(arg
                  ,';');
      var := substr(arg
                   ,1
                   ,i - 1);
      arg := substr(arg
                   ,i + 1);
      p   := p + 1;
      i   := instr(msg
                  ,'[' || to_char(p) || ']');
      if i > 0
      then
        msg := substr(msg
                     ,1
                     ,i - 1) || var ||
               substr(msg
                     ,i + 3);
      else
        return msg;
      end if;
    end loop;
  end translate_text;

  ------------------------------------------------------------------------------
  procedure create_case(p_sop_request    in obj_dbs_send_oppdrag_request
                       ,p_cla_case_no    in cla_case.cla_case_no%type
                       ,p_cla_subcase_no in cla_subcase.cla_subcase_no%type
                       ,p_cla_item_no    in cla_item.cla_item_no%type
                       ,p_sop_response   in obj_dbs_send_oppdrag_response) is
    v_estimate    cla_item.estimate%type;
    v_diff        cla_item.diff%type;
    v_description case_item.letter_desc%type;
    v_comment     case_item.user_comm%type;
    v_error_code  varchar2(10);
    v_case_item   case_item%rowtype;
    v_return_code number;
  
  begin
  
    select cla_case_no
          ,name_id_no
          ,cc.policy_line_no
          ,al.policy_no
      into t8500.rec.claim_no
          ,t8500.rec.name_id_no
          ,t8500.rec.agr_line_no
          ,t8500.rec.policy_no
      from cla_case cc
      join agreement_line al
        on al.agr_line_seq_no = cc.policy_line_seq_no
     where cla_case_no = p_cla_case_no;
  
    select currency_estimate
          ,currency_diff
      into v_estimate
          ,v_diff
      from cla_item
     where cla_item_no = p_cla_item_no
       and newest = 'Y';
  
    if bno72.uf_72_sop_determ_creating_case(p_sop_request
                                           ,v_estimate
                                           ,v_diff) = 1
    then
      if p_sop_response.return_code <> 1
      then
        v_description := substr(x_translate_text('#NO01;' ||
                                                 p_sop_request.estimate_number || ';' ||
                                                 p_sop_request.estimate_version || ';' ||
                                                 v_estimate)
                               ,1
                               ,1024);
        v_comment     := substr(x_translate_text('#NO02;' ||
                                                 p_sop_response.return_code || ';' ||
                                                 p_sop_response.return_text)
                               ,1
                               ,2000);
        v_error_code  := 'NO01';
      else
        v_description := substr(x_translate_text('#NO03;' ||
                                                 p_sop_request.estimate_number || ';' ||
                                                 p_sop_request.estimate_version || ';' ||
                                                 v_estimate)
                               ,1
                               ,1024);
        v_comment     := v_description;
        v_error_code  := 'NO03';
      end if;
    
      bno72.uf_72_pre_create_case(v_error_code
                                 ,0
                                 ,v_comment
                                 ,p_cla_case_no
                                 ,v_case_item
                                 ,v_return_code);
      if v_return_code = 1
      then
        t8500.clr;
        t8500.rec             := v_case_item;
        t8500.rec.user_comm   := v_comment;
        t8500.rec.letter_desc := v_description;
        t8500.ins;
      
      end if;
    end if;
  
  end create_case;

  --------------------------------------------------------------------------
  -- p_error_level:
  --   0,1 Business flow
  --   2 Business error
  --   3 System exception
  --------------------------------------------------------------------------
  procedure create_error_case(p_error_code  in varchar2
                             ,p_error_level in number
                             ,p_cla_case_no in number
                             ,p_val1        in varchar2 := null
                             ,p_val2        in varchar2 := null
                             ,p_val3        in varchar2 := null) is
  
    cursor c_error_description(p_user_id varchar2) is
      select help_text
        from xla_reference_translated_value x
            ,top_user                       u
       where x.table_name = 'STANDARD_MESSAGE'
         and x.language = nvl(u.current_language
                             ,'TIA')
         and x.code = p_error_code
         and u.user_id = p_user_id;
  
    w_comment     varchar2(1024);
    w_case_item   case_item%rowtype;
    w_return_code number;
  
  begin
    if p_val1 is not null
    then
      w_comment := w_comment || p_val1 || ';';
    end if;
    if p_val2 is not null
    then
      w_comment := w_comment || p_val2 || ';';
    end if;
    if p_val3 is not null
    then
      w_comment := w_comment || p_val3 || ';';
    end if;
  
    bno72.uf_72_pre_create_case(p_error_code
                               ,p_error_level
                               ,w_comment
                               ,p_cla_case_no
                               ,w_case_item
                               ,w_return_code);
    if w_return_code = 1
    then
      t8500.clr;
      t8500.rec := w_case_item;
      t8500.ins;
    
    end if;
  
  end create_error_case;

  ----------------------------------------------------------------------------
  --allow update of estimate even if claim is closed (reopen claim)
  procedure reopen_claim(p_cla_case_no in out cla_case.cla_case_no%type) is
    c_program constant varchar2(32) := 'sendOppdrag';
  
  begin
    dbs_trace('Claim is reopened'
             ,c_program);
  
    update cla_case
       set status = 'RO'
     where cla_case_no = p_cla_case_no;
  
  end reopen_claim;
  ----------------------------------------------------------------------------

  procedure reopen_cla_item(p_cla_item_no in out cla_item.cla_item_no%type) is
    c_program constant varchar2(32) := 'sendOppdrag';
    v_cla_item_rec cla_item%rowtype;
  
    cursor c_claim_item is
      select *
        from cla_item
       where status in ('CL'
                       ,'DC'
                       ,'EC')
         and newest = 'Y'
         and subitem_type = 'DBS'
         and cla_item_no = p_cla_item_no;
  
  begin
    p5600.clr;
  
    open c_claim_item;
    fetch c_claim_item
      into v_cla_item_rec;
    if c_claim_item%found
    then
      p5600.cla_item_rec           := v_cla_item_rec;
      p5600.cla_item_rec.status    := 'RO';
      p5600.cla_item_items_changed := ',status,seq_no,';
      p5600.create_claim_item(p_cla_item_no);
      p_cla_item_no := p5600.cla_item_rec.cla_item_no;
    end if;
    close c_claim_item;
  
  end reopen_cla_item;

  ------------------------------------------------------------------------------
  function validate_workshop_data(p_sop_request obj_dbs_send_oppdrag_request)
    return boolean is
  begin
    if p_sop_request.workshop.workshop_number is null
       or p_sop_request.workshop.workshop_name is null
    then
      return false;
    else
      return true;
    end if;
  end validate_workshop_data;

  ------------------------------------------------------------------------------
  procedure create_workshop(p_sop_request in obj_dbs_send_oppdrag_request
                           ,p_id_no       out name.id_no%type) is
    v_ws_name            varchar2(2000);
    v_ws_method          varchar2(2000);
    v_ws_flow            varchar2(2);
    v_ws_tag_name        varchar2(2000);
    v_ws_def_name        varchar2(2000);
    v_is_configurable    varchar2(1);
    v_tia_table_name     varchar2(2000);
    v_tia_column_name    varchar2(2000);
    v_add_condition      varchar2(32000);
    v_user_function      varchar2(1);
    v_user_function_name varchar2(2000);
    c_program constant varchar2(32) := 'sendOppdrag';
  
    procedure fill_name_rec_field(field_value in varchar2) as
    begin
      bno71.get_mapping_details(v_ws_name
                               ,v_ws_method
                               ,v_ws_flow
                               ,v_ws_tag_name
                               ,v_is_configurable
                               ,v_tia_table_name
                               ,v_tia_column_name
                               ,v_add_condition
                               ,v_user_function
                               ,v_user_function_name);
    
      if (v_user_function = 'Y')
      then
        execute immediate '
        begin
          p2000.name_rec.' || v_tia_column_name ||
                          ' := ' || v_user_function_name || '(:p_sop_request);
        end;
      '
          using in p_sop_request;
      else
        execute immediate '
        begin
          p2000.name_rec.' || v_tia_column_name ||
                          ' := :param;
        end;
      '
          using in field_value;
      end if;
    end fill_name_rec_field;
  
  begin
    p2000.clr;
  
    v_ws_name   := 'Oppdrag';
    v_ws_method := 'SendOppdrag';
  
    v_ws_flow     := 'RQ';
    v_ws_def_name := bno71.get_ws_definition(v_ws_name
                                            ,v_ws_method
                                            ,v_ws_flow);
  
    v_ws_tag_name := 'Workshop.WorkshopName';
    fill_name_rec_field(p_sop_request.workshop.workshop_name);
  
    v_ws_tag_name := 'Workshop.WorkshopAddress.Address';
    fill_name_rec_field(p_sop_request.workshop.workshop_address.address);
  
    v_ws_tag_name := 'Workshop.WorkshopAddress.PostalCode';
    fill_name_rec_field(p_sop_request.workshop.workshop_address.postal_code);
  
    v_ws_tag_name := 'Workshop.WorkshopAddress.PostalArea';
    fill_name_rec_field(p_sop_request.workshop.workshop_address.postal_area);
  
    v_ws_tag_name := 'Workshop.Contact';
    fill_name_rec_field(p_sop_request.workshop.contact);
  
    if p_sop_request.workshop.phone is not null
    then
      v_ws_tag_name         := 'Workshop.Phone';
      p2000.telephone_type1 := bno71.get_additional_condition_value(v_ws_def_name
                                                                   ,v_ws_tag_name);
      p2000.phone_no1       := p_sop_request.workshop.phone;
    end if;
  
    if p_sop_request.workshop.email is not null
    then
      v_ws_tag_name         := 'Workshop.Email';
      p2000.telephone_type4 := bno71.get_additional_condition_value(v_ws_def_name
                                                                   ,v_ws_tag_name);
      p2000.phone_no4       := p_sop_request.workshop.email;
    end if;
  
    bno72.uf_72_sop_pre_workshop(p_sop_request);
  
    z_program(gc_package || '.' || c_program);
  
    p2000.create_institution;
  
    p_id_no := p2000.name_rec.id_no;
  end create_workshop;

  ------------------------------------------------------------------------------
  procedure create_role(p_cla_case_no    in cla_case.cla_case_no%type
                       ,p_cla_subcase_no in cla_subcase.cla_subcase_no%type
                       ,p_cla_item_no    in cla_item.cla_item_no%type
                       ,p_wrkshop_id_no  in name.id_no%type) is
    v_count number;
  begin
    select count(*)
      into v_count
      from relation
     where owner = p_cla_case_no
       and member = p_wrkshop_id_no
       and class = 'CCA';
  
    if v_count = 0
       and p_cla_item_no is not null
    then
      select count(*)
        into v_count
        from relation
       where owner = p_cla_item_no
         and member = p_wrkshop_id_no
         and class = 'CIT';
    end if;
    if v_count = 0
    then
      if p_cla_subcase_no is not null
      then
        select count(*)
          into v_count
          from relation
         where owner = p_cla_subcase_no
           and member = p_wrkshop_id_no
           and class = 'CSC';
      
        if v_count = 0
        then
          t2005.clr;
          t2005.rec.member        := p_wrkshop_id_no;
          t2005.rec.owner         := p_cla_subcase_no;
          t2005.rec.relation_type := to_number(nvl(x_site_preference('YNO_DBS_WORKSHOP_RELATION_TYPE')
                                                  ,'7'));
          t2005.rec.class         := 'CSC';
        
          t2005.ins;
        end if;
      
      else
        t2005.clr;
        t2005.rec.member        := p_wrkshop_id_no;
        t2005.rec.owner         := p_cla_case_no;
        t2005.rec.relation_type := to_number(nvl(x_site_preference('YNO_DBS_WORKSHOP_RELATION_TYPE')
                                                ,'7'));
        t2005.rec.class         := 'CCA';
      
        t2005.ins;
      end if;
    end if;
  
  end create_role;

  ------------------------------------------------------------------------------
  procedure create_workshop_fe(p_sop_request in obj_dbs_send_oppdrag_request,
                               p_id_no       out name.id_no%type) is
    c_program constant varchar2(32) := 'sendOppdrag';
  
  begin
  
    bno72.uf_72_create_workshop_fe(p_sop_request, p_id_no);
  
  end create_workshop_fe;

  ------------------------------------------------------------------------------
  procedure create_service_supplier(p_sop_request in obj_dbs_send_oppdrag_request
                                   ,p_verkstedid  in varchar2
                                   ,p_name_id_no  in out name.id_no%type) is
  
    w_is_configurable    varchar2(1);
    w_tia_table_name     varchar2(2000);
    w_tia_column_name    varchar2(2000);
    w_add_condition      varchar2(32000);
    w_user_function      varchar2(1);
    w_user_function_name varchar2(2000);
    w_update_sql         varchar2(2000);
  
    cursor c_service_supplier is
      select name_id_no
        from ssu_service_supplier
       where name_id_no = p_name_id_no;
  
    w_service_supplier_id_no ssu_service_supplier.name_id_no%type;
  
  begin
    open c_service_supplier;
    fetch c_service_supplier
      into w_service_supplier_id_no;
    if c_service_supplier%notfound
    then
      t3550.clr;
      t3550.rec.name_id_no := p_name_id_no;
      bno72.uf_72_sop_get_serv_supp_data(p_sop_request
                                        ,p_verkstedid
                                        ,t3550.rec);
      t3550.ins;
    
      --setting verkstedid in field described in mapping
      bno71.get_mapping_details('SOP_RQ'
                               ,'Workshop.WorkshopNumber'
                               ,w_is_configurable
                               ,w_tia_table_name
                               ,w_tia_column_name
                               ,w_add_condition
                               ,w_user_function
                               ,w_user_function_name);
      w_update_sql := 'update ssu_service_supplier set ' ||
                      w_tia_column_name ||
                      '= :verkstedid where name_id_no = :name_id_no ';
      execute immediate w_update_sql
        using in p_verkstedid, p_name_id_no;
    end if;
    close c_service_supplier;
  
  end create_service_supplier;

  ------------------------------------------------------------------------------
  procedure create_service_supplier_case(p_sop_request     in obj_dbs_send_oppdrag_request
                                        ,p_cla_case_no     in number
                                        ,p_verkstedid      in varchar2
                                        ,p_wrkshop_id_no   in name.id_no%type
                                        ,p_oppdrags_nr     in varchar2
                                        ,p_ser_sup_case_no out ssu_service_supplier_case.ssu_ser_sup_case_no%type) is
  
    w_claimant_id_no  name.id_no%type;
    w_ser_sup_case_no ssu_service_supplier_case.ssu_ser_sup_case_no%type;
  
    cursor c_service_supplier_case(p_claimant_id_no name.id_no%type) is
      select ssu_ser_sup_case_no
        from ssu_service_supplier_case
       where claimant_id_no = p_claimant_id_no
         and cla_case_no = p_cla_case_no
         and name_id_no = p_wrkshop_id_no
         and reference_no = p_oppdrags_nr;
  
  begin
  
    select name_id_no
      into w_claimant_id_no
      from cla_case
     where cla_case_no = p_cla_case_no;
  
    open c_service_supplier_case(w_claimant_id_no);
    fetch c_service_supplier_case
      into w_ser_sup_case_no;
    if c_service_supplier_case%notfound
    then
      t3500.clr;
      t3500.rec.claimant_id_no := w_claimant_id_no;
      t3500.rec.cla_case_no    := p_cla_case_no;
      t3500.rec.name_id_no     := p_wrkshop_id_no;
      t3500.rec.reference_no   := p_oppdrags_nr;
    
      bno72.uf_72_sop_get_ssu_case_data(p_sop_request
                                       ,p_verkstedid
                                       ,p_wrkshop_id_no
                                       ,t3500.rec);
    
      t3500.ins;
    end if;
    close c_service_supplier_case;
  
  end create_service_supplier_case;

  ------------------------------------------------------------------------------
  procedure create_cla_item(p_sop_request    in obj_dbs_send_oppdrag_request
                           ,p_cla_case_no    in cla_case.cla_case_no%type
                           ,p_cla_subcase_no in cla_subcase.cla_subcase_no%type
                           ,p_wrkshop_id_no  in name.id_no%type
                           ,p_cla_item_no    in out cla_item.cla_item_no%type
                           ,p_sop_response   in out obj_dbs_send_oppdrag_response
                           ,p_oppdrags_nr    in out varchar2) is
    c_program constant varchar2(32) := 'sendOppdrag';
    v_ws_name            varchar2(2000);
    v_ws_method          varchar2(2000);
    v_ws_flow            varchar2(2);
    v_ws_tag_name        varchar2(2000);
    v_is_configurable    varchar2(1);
    v_tia_table_name     varchar2(2000);
    v_tia_column_name    varchar2(2000);
    v_add_condition      varchar2(32000);
    v_user_function      varchar2(1);
    v_user_function_name varchar2(2000);
    v_cla_event_no       cla_item.cla_event_no%type;
    v_count              number;
    v_estimate           cla_item.estimate%type;
    v_items_changed      varchar2(32000) := ',';
    v_paid_invoice_sum   number := 0;
    v_risk_no            cla_case.risk_no%type;
    v_subrisk_no         cla_case.subrisk_no%type;
    v_al_seq_no          agreement_line.agr_line_seq_no%type;
    v_claim_type         varchar2(50);
  
    cursor c_paid_items is
      select ci.cla_item_no
            ,ci.item_type
            ,nvl(sum(cpi.currency_amount)
                ,0) as currency_amount
        from cla_item ci
        left outer join cla_payment_item cpi
          on cpi.cla_item_no = ci.cla_item_no
       where ci.cla_case_no = p_cla_case_no
         and ci.newest = 'Y'
         and ci.subitem_type = 'DBS'
       group by ci.cla_item_no
               ,ci.item_type;
  
    procedure fill_cla_item_rec(field_value varchar2) as
    begin
      bno71.get_mapping_details(v_ws_name
                               ,v_ws_method
                               ,v_ws_flow
                               ,v_ws_tag_name
                               ,v_is_configurable
                               ,v_tia_table_name
                               ,v_tia_column_name
                               ,v_add_condition
                               ,v_user_function
                               ,v_user_function_name);
    
      if (v_user_function = 'Y')
      then
        execute immediate '
        begin
          p5600.cla_item_rec.' ||
                          v_tia_column_name || ' := ' ||
                          v_user_function_name || '(:p_sop_request);
        end;
      '
          using in p_sop_request;
      else
        execute immediate '
        begin
          p5600.cla_item_rec.' ||
                          v_tia_column_name || ' := :param;
        end;
      '
          using in field_value;
      end if;
    
      v_items_changed := v_items_changed || v_tia_column_name || ',';
    
    end fill_cla_item_rec;
  begin
    p5600.clr;
  
    select cla_event_no
      into v_cla_event_no
      from cla_case
     where cla_case_no = p_cla_case_no;
  
    p5600.cla_item_rec.cla_event_no   := v_cla_event_no;
    p5600.cla_item_rec.cla_case_no    := p_cla_case_no;
    p5600.cla_item_rec.cla_subcase_no := p_cla_subcase_no;
  
    p5600.cla_item_rec.description := substr('DBS Oppdrags ' ||
                                             p_sop_request.estimate_number || ' ' ||
                                             p_sop_request.estimate_version
                                            ,1
                                            ,2000);
    v_items_changed                := v_items_changed || 'description,';
  
    p5600.cla_item_rec.receiver_id_no := p_wrkshop_id_no;
    v_items_changed                   := v_items_changed ||
                                         'receiver_id_no,';
  
    select cc.policy_line_seq_no
      into v_al_seq_no
      from cla_case cc
      join agreement_line al
        on al.agr_line_seq_no = cc.policy_line_seq_no
     where cc.cla_case_no = p_cla_case_no;
  
    v_claim_type := bno72.convert_damagetype_id(p_sop_request.damage_type_id);
  
    v_risk_no := bno72.uf_72_get_risk_no(c_program
                                         
                                        ,v_claim_type
                                        ,bno72.claim_item_table_name
                                        ,v_al_seq_no);
    if v_risk_no is null
    then
      create_error_case('NO09'
                       ,0
                       ,p_cla_case_no
                       ,v_claim_type
                       ,bno72.claim_item_table_name
                       ,v_al_seq_no);
    else
      p5600.cla_item_rec.risk_no := v_risk_no;
    end if;
  
    v_subrisk_no := bno72.uf_72_get_subrisk_no(c_program
                                              ,v_claim_type
                                              ,bno72.claim_item_table_name
                                              ,v_al_seq_no);
    if v_subrisk_no is null
    then
      create_error_case('NO10'
                       ,0
                       ,p_cla_case_no
                       ,v_claim_type
                       ,bno72.claim_item_table_name
                       ,v_al_seq_no);
    else
      p5600.cla_item_rec.subrisk_no := v_subrisk_no;
    end if;
  
    if p_cla_item_no is null
    then
      p5600.cla_item_rec.status := 'OP';
    end if;
  
    p5600.cla_item_rec.handler := x_site_preference('YNO_DBS_ESTIMATOR');
    v_items_changed            := v_items_changed || 'handler,';
  
    p5600.cla_item_rec.item_type     := 'RE';
    p5600.cla_item_rec.subitem_type  := 'DBS';
    p5600.cla_item_rec.currency_code := 'NOK';
  
    select object_id
          ,object_no
          ,object_seq_no
      into p5600.cla_item_rec.object_id
          ,p5600.cla_item_rec.object_no
          ,p5600.cla_item_rec.object_seq_no
      from cla_case
     where cla_case_no = p_cla_case_no;
  
    if p_cla_item_no is not null
    then
      for rec in c_paid_items
      loop
        if rec.item_type = 'RE'
        then
          v_paid_invoice_sum := v_paid_invoice_sum + rec.currency_amount;
        end if;
      end loop;
    end if;
  
    v_estimate := bno72.round_decimals(bno72.uf_72_sop_choose_sum(p_cla_case_no
                                                                 ,p_cla_subcase_no));
  
    z_program(gc_package || '.' || c_program);
  
    p5600.cla_item_rec.currency_estimate := bno72.round_decimals(v_estimate -
                                                                 v_paid_invoice_sum);
  
    v_items_changed := v_items_changed || 'currency_estimate,';
    v_items_changed := v_items_changed || 'currency_diff,';
    v_items_changed := v_items_changed || 'estimate,';
    v_items_changed := v_items_changed || 'diff,';
  
    -- Save OppdragsNr, OppdragsData.versjonsNr, Statustekst, Kondemnasjonskode in flex fields
    v_ws_name   := 'Oppdrag';
    v_ws_method := 'SendOppdrag';
    v_ws_flow   := 'RQ';
  
    v_ws_tag_name := 'EstimateNumber';
    fill_cla_item_rec(p_sop_request.estimate_number);
  
    v_ws_tag_name := 'EstimateVersion';
    fill_cla_item_rec(p_sop_request.estimate_version);
  
    v_ws_tag_name := 'EstimateOfferStatusId';
    fill_cla_item_rec(p_sop_request.estimate_offer_status_id);
  
    v_ws_tag_name := 'Vehicle.CondemnationCode';
    fill_cla_item_rec(p_sop_request.vehicle.condemnation_code);
  
    if p_oppdrags_nr is null
    then
      p5600.cla_item_rec.role := null;
      v_items_changed         := v_items_changed || 'role,';
    end if;
  
    if p_cla_item_no is not null
    then
      v_items_changed              := v_items_changed || 'seq_no,';
      p5600.cla_item_items_changed := v_items_changed;
    end if;
  
    p5600.create_claim_item(p_cla_item_no);
  
    p_cla_item_no := p5600.cla_item_rec.cla_item_no;
  
    -- Check if there is referral on cla_case
    select count(*)
      into v_count
      from cla_case
     where cla_case.referral_code is not null
       and cla_case_no = p_cla_case_no;
  
    if v_count > 0
    then
      set_decision(p_sop_response
                  ,'8'
                  ,'50');
    end if;
  
  end create_cla_item;
  ----------------------------------------------------------------------------

  procedure sendoppdrag(p_input_token in obj_input_token
                       ,p_request     in obj_dbs_send_oppdrag_request
                       ,p_response    out nocopy obj_dbs_send_oppdrag_response
                       ,p_result      out nocopy obj_result) is
    c_program          constant varchar2(32) := 'sendOppdrag';
    c_operation_number constant varchar2(3) := '010';
    c_msg_id_other     constant varchar2(17) := 'DBS-OPP-010-99999';
    v_ws_name              varchar2(2000);
    v_ws_method            varchar2(2000);
    v_ws_flow              varchar2(2);
    v_ws_tag_name          varchar2(2000);
    v_ws_def_name          yno_dbs_mapping.ws_def_name%type;
    v_is_configurable      varchar2(1);
    v_tia_table_name       varchar2(2000);
    v_tia_column_name      varchar2(2000);
    v_add_condition        varchar2(32000);
    v_user_function        varchar2(1);
    v_user_function_name   varchar2(2000);
    v_input_token          obj_input_token;
    w_logging_req_seq_no   number;
    v_temp_char            varchar2(32000);
    v_temp_number          number;
    v_temp_date            date;
    v_query                varchar2(32000);
    v_temp_query           varchar2(32000);
    v_where                varchar2(32000);
    v_cursor               sys_refcursor;
    v_cla_case_no          number(10
                                 ,0);
    v_cla_status           cla_case.status%type;
    v_cla_subcase_no       number(10
                                 ,0);
    v_cla_subcase_status   cla_subcase.status%type;
    v_cla_item_no          number(10
                                 ,0);
    v_cla_item_status      cla_item.status%type;
    v_count                number;
    v_req_oppdrags_nr      varchar2(8);
    v_req_oppdrags_versjon number;
    v_oppdrags_nr          varchar2(8);
    v_oppdrags_versjon     number;
    v_wrkshop_id_no        name.id_no%type;
    v_ser_sup_case_no      ssu_service_supplier_case.ssu_ser_sup_case_no%type;
    v_dbs_cla_items_count  number;
    v_cla_item_count       number;
    err_msg                varchar2(1000);
  
    function get_varchar2_from_rq(field_value varchar2) return varchar2 is
      varchar_value varchar2(2000);
    begin
      bno71.get_mapping_details(v_ws_name
                               ,v_ws_method
                               ,v_ws_flow
                               ,v_ws_tag_name
                               ,v_is_configurable
                               ,v_tia_table_name
                               ,v_tia_column_name
                               ,v_add_condition
                               ,v_user_function
                               ,v_user_function_name);
    
      if (v_user_function = 'Y')
      then
        execute immediate '
        begin
          :v_temp_char := ' ||
                          v_user_function_name || '(:p_request);
        end;
      '
          using out varchar_value, in p_request;
      else
        varchar_value := field_value;
      end if;
    
      return varchar_value;
    end get_varchar2_from_rq;
  
  begin
    -- Initialize everything
    if p_input_token is null
    then
      v_input_token         := obj_input_token();
      v_input_token.user_id := x_site_preference('YNO_DBS_CLAIM_USER_ID');
    else
      v_input_token := p_input_token;
    end if;
  
    utl_foundation.init_operation(p_input_token => v_input_token
                                 ,p_service     => gc_package
                                 ,p_operation   => c_program);
  
    trace_configuration;
    dbs_trace('START sendOppdrag'
             ,c_program);
  
  
    bno74.log_sendoppdrag_request(p_request
                                 ,w_logging_req_seq_no);
    bno72.gw_obj_dbs_sop_request := p_request;
  
    v_ws_name   := 'Oppdrag';
    v_ws_method := 'SendOppdrag';
  
    p_response := obj_dbs_send_oppdrag_response();
  
    -- Check if messagecode is 100, 110, 111 or 190 or  - otherwise ignore
    v_temp_char := get_varchar2_from_rq(p_request.message_code);
    
    if nvl(v_temp_char
          ,' ') not in ('100',
                        '110',
                        '111',
                        '190')
    then
      dbs_trace('Got unknown message_code: ' || v_temp_char ||
                '. Ignoring request'
               ,c_program);
               
      set_decision(p_response
                  ,'9'
                  ,'90');
      p_response.return_text := substr(p_response.return_text || ' Invalid message_code: ' || v_temp_char || '. Ignoring request'
                                      ,1
                                      ,1000);
      return;
    end if;
  
    -- Attempt to check if claim case no equal to Company.ClaimNumber exists.
    v_ws_flow     := 'RQ';
    v_ws_tag_name := 'Company.ClaimNumber';
    v_temp_char   := get_varchar2_from_rq(p_request.company.claim_number);
  
    if v_temp_char is null
    then
      -- Invalid request, there is no skade Nr
      set_decision(p_response
                  ,'8'
                  ,'60');
      goto end_main;
    end if;
  
    if x_site_preference('YNO_DBS_CHECK_ANSV_REGNR') = 'Y'
    then
      if p_request.damage_type_id = bno72.claim_type_ansvar_no
         and p_request.company.insurance_licence_number is null
      then
        -- Invalid request, there is no reg nr
        set_decision(p_response
                    ,'8'
                    ,'62');
        goto end_main;
      end if;
    end if;
  
    v_query := 'SELECT cla_case_no, status
    FROM cla_case
    WHERE ' || v_tia_column_name || ' = :skadenr';
  
    if length(v_add_condition) is not null
    then
      v_query := v_query || ' AND ' || v_add_condition;
    end if;
  
    open v_cursor for v_query
      using v_temp_char;
    fetch v_cursor
      into v_cla_case_no
          ,v_cla_status;
    close v_cursor;
  
    -- Check claim existing
    if v_cla_case_no is null
    then
      set_decision(p_response
                  ,'8'
                  ,'10');
      goto end_main;
    end if;
  
    -- Check claim status
    --P3571 allow update of estimate even if claim is closed (reopen claim)
    if v_cla_status in ('DC'
                       ,'EC')
    then
      set_decision(p_response
                  ,'8'
                  ,'20');
      goto end_main;
    end if;
  
    -- allow update of estimate even if claim is closed (reopen claim)
    if v_cla_status is not null
       and v_cla_status in ('CL')
    then
      reopen_claim(v_cla_case_no);
      create_error_case('NO98'
                       ,0
                       ,v_cla_case_no);
    end if;
  
    bno72.uf_72_sop_get_subcase(p_request
                               ,v_cla_case_no
                               ,v_cla_subcase_no
                               ,p_response);
    z_program(gc_package || '.' || c_program);
  
    if p_response is not null
       and p_response.return_code > 1
    then
      goto end_main;
    end if;
  
    if v_cla_subcase_no is not null
    then
      -- Check claim subcase existing if necessary
      v_query := 'SELECT cla_subcase_no, status
      FROM cla_subcase
      WHERE cla_subcase_no = :cla_subcase_no';
    
      open v_cursor for v_query
        using v_cla_subcase_no;
      fetch v_cursor
        into v_cla_subcase_no
            ,v_cla_subcase_status;
    
      if v_cursor%notfound
      then
        close v_cursor;
        set_decision(p_response
                    ,'8'
                    ,'11');
        goto end_main;
      end if;
    
      close v_cursor;
    
      -- Check claim subcase status
      if v_cla_subcase_status in ('CL'
                                 ,'DC'
                                 ,'EC')
      then
        set_decision(p_response
                    ,'8'
                    ,'21');
        goto end_main;
      end if;
    end if;
  
    -- Refferenial integrity check for skadenr and forsavtal
    if p_request.company.insurance_number is not null
    then
      dbs_trace('Checking refferenial integrity for skadenr and forsavtal'
               ,c_program);
      v_ws_tag_name := 'Company.InsuranceNumber';
      v_temp_char   := get_varchar2_from_rq(p_request.company.insurance_number);
    
      v_query := 'SELECT count(*)
      INTO :v_count
      FROM cla_case cc
      JOIN agreement_line al on al.agr_line_seq_no = cc.policy_line_seq_no
      WHERE cc.cla_case_no = :v_cla_case_no
        AND al.' || v_tia_column_name || ' = :v_forsavtal';
    
      if length(v_add_condition) is not null
      then
        v_query := v_query || ' AND ' || v_add_condition;
      end if;
    
      open v_cursor for v_query
        using v_cla_case_no, v_temp_char;
      fetch v_cursor
        into v_count;
      close v_cursor;
    
      if v_count = 0
      then
        set_decision(p_response
                    ,'8'
                    ,'80');
        goto end_main;
      end if;
    end if;
  
    --referential integrity check varies depending on whether site preference is set or not
    if x_site_preference('YNO_DBS_CHECK_ANSV_REGNR') = 'Y'
    then
      -- Refferenial integrity check for skadenr and regnr
      dbs_trace('Checking refferenial integrity for skadenr and regnr'
               ,c_program);
      if p_request.damage_type_id = bno72.claim_type_ansvar_no
      then
        v_ws_tag_name := 'Company.InsuranceLicenceNumber';
        v_temp_char   := get_varchar2_from_rq(p_request.company.insurance_licence_number);
      else
        v_ws_tag_name := 'Vehicle.LicenceNumber';
        v_temp_char   := get_varchar2_from_rq(p_request.vehicle.licence_number);
      end if;
    
      v_ws_def_name := bno71.get_ws_definition(v_ws_name
                                              ,v_ws_method
                                              ,v_ws_flow);
    
      if v_cla_subcase_no is not null
      then
        v_query := 'SELECT count(*)
      INTO :v_count
      FROM cla_subcase cs
      JOIN object o on o.seq_no = cs.object_seq_no
      WHERE cs.cla_subcase_no = :v_cla_subcase_no
        AND o.' ||
                   bno71.get_obj_column_name_claim_no(v_ws_def_name
                                                     ,v_ws_tag_name
                                                     ,v_cla_case_no
                                                     ,v_cla_subcase_no) ||
                   ' = :v_regnr';
      
        v_temp_number := v_cla_subcase_no;
      else
        v_query       := 'SELECT count(*)
      INTO :v_count
      FROM cla_case cc
      JOIN object o on o.seq_no = cc.object_seq_no
      WHERE cc.cla_case_no = :v_cla_case_no
        AND o.' ||
                         bno71.get_obj_column_name_claim_no(v_ws_def_name
                                                           ,v_ws_tag_name
                                                           ,v_cla_case_no) ||
                         ' = :v_regnr';
        v_temp_number := v_cla_case_no;
      end if;
    
      if length(v_add_condition) is not null
      then
        v_query := v_query || ' AND ' || v_add_condition;
      end if;
    
      open v_cursor for v_query
        using v_temp_number, v_temp_char;
      fetch v_cursor
        into v_count;
      close v_cursor;
    
      if v_count = 0
      then
        set_decision(p_response
                    ,'8'
                    ,'82');
        goto end_main;
      end if;
    else
      --referrential check for claim number and regnr
      --First check if regnr is policyholder
      v_ws_tag_name := 'Vehicle.LicenceNumber';
      v_temp_char   := get_varchar2_from_rq(p_request.vehicle.licence_number);
    
      v_ws_def_name := bno71.get_ws_definition(v_ws_name
                                              ,v_ws_method
                                              ,v_ws_flow);
    
      if v_cla_subcase_no is not null
      then
        v_query := 'SELECT count(*)
      INTO :v_count
      FROM cla_subcase cs
      JOIN object o on o.seq_no = cs.object_seq_no
      WHERE cs.cla_subcase_no = :v_cla_subcase_no
        AND o.' ||
                   bno71.get_obj_column_name_claim_no(v_ws_def_name
                                                     ,v_ws_tag_name
                                                     ,v_cla_case_no
                                                     ,v_cla_subcase_no) ||
                   ' = :v_regnr';
      
        v_temp_number := v_cla_subcase_no;
      else
        v_query       := 'SELECT count(*)
      INTO :v_count
      FROM cla_case cc
      JOIN object o on o.seq_no = cc.object_seq_no
      WHERE cc.cla_case_no = :v_cla_case_no
        AND o.' ||
                         bno71.get_obj_column_name_claim_no(v_ws_def_name
                                                           ,v_ws_tag_name
                                                           ,v_cla_case_no) ||
                         ' = :v_regnr';
        v_temp_number := v_cla_case_no;
      end if;
    
      if length(v_add_condition) is not null
      then
        v_query := v_query || ' AND ' || v_add_condition;
      end if;
    
      open v_cursor for v_query
        using v_temp_number, v_temp_char;
      fetch v_cursor
        into v_count;
      close v_cursor;
    
      if v_count = 0
      then
        dbs_trace('Regnr: ' || v_temp_char || ' findes ikke på skade: ' ||
                  v_cla_case_no ||
                  ' som forsikringstager, prøv som modpart'
                 ,c_program);
        -- then check if regnr is third party
        v_query := 'select count(*)
      INTO :v_count
      from cla_case cla_case
      join cla_event cla_event on cla_case.cla_event_no = cla_event.cla_event_no
      join policy_line policy_line on cla_case.policy_line_seq_no = policy_line.agr_line_seq_no
      join policy policy on policy_line.policy_seq_no = policy.policy_seq_no
      join object object on cla_case.object_seq_no = object.seq_no
      join cla_third_party cla_third_party on cla_case.cla_case_no = cla_third_party.cla_case_no
      where cla_case.cla_case_no =  :v_cla_case_no and cla_third_party.' ||
                   bno72.uf_72_third_party_reg_col || ' = :v_temp_char ';
      
        dbs_trace('v_query: ' || v_query
                 ,c_program);
      
        open v_cursor for v_query
          using v_temp_number, v_temp_char;
        fetch v_cursor
          into v_count;
        close v_cursor;
      
        if v_count = 0
        then
          dbs_trace('Regnr: ' || v_temp_char || ' findes ikke på skade: ' ||
                    v_cla_case_no || ' som modpart'
                   ,c_program);
          set_decision(p_response
                      ,'8'
                      ,'82');
          goto end_main;
        end if;
      
      end if;
    
    end if;
  
    -- Refferenial integrity check for skadenr and skadedato
    -- only if damage_date is present
    if p_request.damage_date is not null
    then
      dbs_trace('Checking refferenial integrity for skadenr and skadedato'
               ,c_program);
      v_ws_tag_name := 'DamageDate';
      bno71.get_mapping_details(v_ws_name
                               ,v_ws_method
                               ,v_ws_flow
                               ,v_ws_tag_name
                               ,v_is_configurable
                               ,v_tia_table_name
                               ,v_tia_column_name
                               ,v_add_condition
                               ,v_user_function
                               ,v_user_function_name);
    
      if (v_user_function = 'Y')
      then
        execute immediate '
      begin
        :v_temp_date := ' || v_user_function_name ||
                          '(:p_sop_request);
      end;
    '
          using out v_temp_date, in p_request;
      else
        v_temp_date := p_request.damage_date;
      end if;
    
      v_query := 'SELECT count(*)
    INTO :v_count
    FROM cla_case cc
    JOIN cla_event ce on ce.cla_event_no = cc.cla_event_no
    WHERE cc.cla_case_no = :v_cla_case_no
      AND trunc(ce.' || v_tia_column_name ||
                 ', ''DDD'') = trunc(:v_skadedato, ''DDD'')';
    
      if length(v_add_condition) is not null
      then
        v_query := v_query || ' AND ' || v_add_condition;
      end if;
    
      open v_cursor for v_query
        using v_cla_case_no, v_temp_date;
      fetch v_cursor
        into v_count;
      close v_cursor;
    
      if v_count = 0
      then
        set_decision(p_response
                    ,'8'
                    ,'81');
        goto end_main;
      end if;
    end if;
  
    -- Check claim item existing
    dbs_trace('Checking if claim item exists.'
             ,c_program);
    v_ws_tag_name := 'EstimateVersion';
    bno71.get_mapping_details(v_ws_name
                             ,v_ws_method
                             ,v_ws_flow
                             ,v_ws_tag_name
                             ,v_is_configurable
                             ,v_tia_table_name
                             ,v_tia_column_name
                             ,v_add_condition
                             ,v_user_function
                             ,v_user_function_name);
    v_query := 'SELECT cla_item_no, status';
    v_query := v_query || ', ' || v_tia_column_name;
  
    if (v_user_function = 'Y')
    then
      execute immediate '
      begin
        :v_temp_char := ' || v_user_function_name ||
                        '(:p_sop_request);
      end;
  '
        using out v_temp_char, in p_request;
    else
      v_temp_char := p_request.estimate_version;
    end if;
    v_req_oppdrags_versjon := v_temp_char;
  
    v_ws_tag_name := 'EstimateNumber';
    bno71.get_mapping_details(v_ws_name
                             ,v_ws_method
                             ,v_ws_flow
                             ,v_ws_tag_name
                             ,v_is_configurable
                             ,v_tia_table_name
                             ,v_tia_column_name
                             ,v_add_condition
                             ,v_user_function
                             ,v_user_function_name);
    v_query := v_query || ', ' || v_tia_column_name;
  
    if (v_user_function = 'Y')
    then
      execute immediate '
      begin
        :v_temp_char := ' || v_user_function_name ||
                        '(:p_sop_request);
      end;
  '
        using out v_temp_char, in p_request;
    else
      v_temp_char := p_request.estimate_number;
    end if;
    v_req_oppdrags_nr := v_temp_char;
  
    dbs_trace('Request estimate_number=' || v_req_oppdrags_nr ||
              ' estimate_version=' || v_req_oppdrags_versjon
             ,c_program);
  
    --checking if there is cla_item with oppdragsnr
    dbs_trace('Checking if there is cla_item with oppdragsnr.'
             ,c_program);
    v_query := v_query || '
     FROM cla_item
    WHERE cla_case_no = :cla_case_no
      AND newest = ''Y''
      AND item_type = ''RE''
      AND subitem_type = ''DBS''';
  
    v_where      := ' AND ' || v_tia_column_name || ' = :oppdragsnr';
    v_temp_query := v_query || v_where;
  
    if length(v_add_condition) is not null
    then
      v_temp_query := v_temp_query || ' AND ' || v_add_condition;
    end if;
  
    dbs_trace('v_temp_query: ' || v_temp_query
             ,c_program);
  
    open v_cursor for v_temp_query
      using v_cla_case_no, v_temp_char;
    fetch v_cursor
      into v_cla_item_no
          ,v_cla_item_status
          ,v_oppdrags_versjon
          ,v_oppdrags_nr;
    close v_cursor;
  
    dbs_trace('Found cla_item: v_cla_item_no=' || v_cla_item_no ||
              ' v_cla_item_status=' || v_cla_item_status ||
              ' v_oppdrags_versjon=' || v_oppdrags_versjon ||
              ' v_oppdrags_nr=' || v_oppdrags_nr
             ,c_program);
  
    --checking if there is cla_item without oppdragsnr
    dbs_trace('Checking if there is cla_item without oppdragsnr. ' ||
              v_oppdrags_nr
             ,c_program);
    if v_cla_item_no is null
    then
      v_where      := ' AND ' || v_tia_column_name || ' is null';
      v_temp_query := v_query || v_where;
    
      if length(v_add_condition) is not null
      then
        v_temp_query := v_temp_query || ' AND ' || v_add_condition;
      end if;
    
      open v_cursor for v_temp_query
        using v_cla_case_no;
      fetch v_cursor
        into v_cla_item_no
            ,v_cla_item_status
            ,v_oppdrags_versjon
            ,v_oppdrags_nr;
      close v_cursor;
    end if;
  
    -- Check if estimate_number and estimate_version is already known...
    dbs_trace('Checking if estimate_number=' || v_req_oppdrags_nr ||
              ' estimate_version=' || v_req_oppdrags_versjon ||
              ' is a duplicate or lesser version.'
             ,c_program);
    if v_oppdrags_nr is not null
       and v_oppdrags_versjon is not null
    then
      if v_req_oppdrags_nr = v_oppdrags_nr
         and v_req_oppdrags_versjon <= v_oppdrags_versjon
      then
        set_decision(p_response
                    ,'7'
                    ,'22');
        goto end_main;
      end if;
    end if;
  
    -- Check if claim item is open if exists.
    dbs_trace('Checking if claim item is open if exists.'
             ,c_program);
    dbs_trace('DamageTypeId: ' || p_request.damage_type_id
             ,c_program);
    if p_request.damage_type_id = bno72.claim_type_glass_no
    then
      if v_cla_item_status is not null
         and v_cla_item_status not in ('OP'
                                      ,'NO'
                                      ,'RO')
      then
        set_decision(p_response
                    ,'8'
                    ,'30');
        goto end_main;
      end if;
    else
      if v_cla_item_status is not null
         and v_cla_item_status not in ('CL'
                                      ,'OP'
                                      ,'NO'
                                      ,'RO')
      then
        set_decision(p_response
                    ,'8'
                    ,'30');
        goto end_main;
      end if;
      --General case (closed claim, claim item must be reopened)
      if v_cla_item_status is not null
         and v_cla_item_status in ('CL')
      then
        reopen_cla_item(v_cla_item_no);
        create_error_case('NO04'
                         ,0
                         ,v_cla_case_no);
      end if;
    end if;
  
    -- check if workshop exists
    dbs_trace('Checking if workshop exists.'
             ,c_program);
    if validate_workshop_data(p_request) = false
    then
      set_decision(p_response
                  ,'8'
                  ,'40');
      goto end_main;
    end if;
  
    v_query := 'SELECT name_id_no
    FROM ssu_service_supplier
    WHERE ';
  
    v_ws_tag_name := 'Workshop.WorkshopNumber';
    v_temp_char   := get_varchar2_from_rq(p_request.workshop.workshop_number);
  
    v_query := v_query || v_tia_column_name || ' = :verkstedid';
  
    if length(v_add_condition) is not null
    then
      v_query := v_query || ' AND ' || v_add_condition;
    end if;
  
    open v_cursor for v_query
      using v_temp_char;
    fetch v_cursor
      into v_wrkshop_id_no;
    close v_cursor;
    
    BNO72.uf_72_find_workshop(p_oppdrag_request=> p_request
                              ,p_workshop_id => v_wrkshop_id_no);
    
    if v_wrkshop_id_no is null
    then
      -- create workshop entry
      dbs_trace('Creating workshop entry.'
               ,c_program);
      create_workshop(p_request
                     ,v_wrkshop_id_no);
    end if;
  
    if x_site_preference('YNO_DBS_WORKSHOP_AS_SSU') = 'Y'
    then
      create_service_supplier(p_request
                             ,v_temp_char
                             ,v_wrkshop_id_no);
      create_service_supplier_case(p_request
                                  ,v_cla_case_no
                                  ,v_temp_char
                                  ,v_wrkshop_id_no
                                  ,v_req_oppdrags_nr
                                  ,v_ser_sup_case_no);
    else
      create_role(v_cla_case_no
                 ,v_cla_subcase_no
                 ,v_cla_item_no
                 ,v_wrkshop_id_no);
      create_service_supplier(p_request
                             ,v_temp_char
                             ,v_wrkshop_id_no);
    end if;
  
    begin
    
      --checking if there is existing cla_item
      v_query := 'SELECT count (*) FROM cla_item WHERE cla_case_no = :cla_case_no AND subitem_type = ''DBS''';
      if v_cla_subcase_no is not null
      then
        v_query := v_query || ' AND cla_subcase_no = ' || v_cla_subcase_no;
      end if;
      open v_cursor for v_query
        using v_cla_case_no;
      fetch v_cursor
        into v_dbs_cla_items_count;
      close v_cursor;
    
      -- create or update cla_item
      dbs_trace('Creating or updating cla_item.'
               ,c_program);
      create_cla_item(p_request
                     ,v_cla_case_no
                     ,v_cla_subcase_no
                     ,v_wrkshop_id_no
                     ,v_cla_item_no
                     ,p_response
                     ,v_oppdrags_nr);
    
      --Checking if there is more than one estimate.
      --If yes, the Recovery item shouldn't be updated and acceptance code must be set to 'MAN'
      v_query := 'SELECT count (*)
      FROM cla_item
      WHERE cla_case_no = :cla_case_no
      AND newest = ''Y''
      AND item_type = ''RE''
      AND subitem_type = ''DBS''';
    
      if v_cla_subcase_no is not null
      then
        v_query := v_query || ' AND cla_subcase_no = ' || v_cla_subcase_no;
      end if;
    
      open v_cursor for v_query
        using v_cla_case_no;
      fetch v_cursor
        into v_count;
      close v_cursor;
    
      if v_dbs_cla_items_count = 0
      then
        v_cla_item_count := 0;
      else
        v_cla_item_count := v_count;
      end if;
    
      if v_count > 1
      then
        create_error_case('NO05'
                         ,0
                         ,v_cla_case_no);
      else
        -- correct RC cla_item if exists
        bno72.uf_72_sop_correct_recovery(p_request
                                        ,v_cla_case_no
                                        ,v_cla_subcase_no);
      end if;
      -- handling acceptance codes
      bno72.uf_72_sop_handle_accept_codes(p_request
                                         ,v_cla_case_no
                                         ,v_cla_item_count);
    
    exception
      when others then
        if (p0000.tia_appl_error_generic_code = sqlcode)
           and (instr(sqlerrm
                     ,'check_event_for_lock') > 0)
        then
        
          set_decision(p_response
                      ,'8'
                      ,'70');
        
          goto end_main;
        else
          z_error;
        end if;
    end;
  
    -- Automatic acceptance rules:
    p_response.return_code := '1';
  
    bno72.uf_72_sop_acceptance_rule(p_request
                                   ,v_cla_case_no
                                   ,v_cla_subcase_no
                                   ,v_cla_item_no
                                   ,v_wrkshop_id_no
                                   ,p_response);
  
    z_program(gc_package || '.' || c_program);
  
    -- create case
    create_case(p_request
               ,v_cla_case_no
               ,v_cla_subcase_no
               ,v_cla_item_no
               ,p_response);
  
    bno72.uf_72_sop_pre_send_response(p_request
                                     ,p_response);
  
    <<end_main>>
    if p_response is not null
       and p_response.return_code > 1
    then
      create_error_case('NO23'
                       ,2
                       ,v_cla_case_no
                       ,p_response.return_code
                       ,p_response.return_text);
    end if;

    bno74.log_sendoppdrag_response(p_request_seq_no  => w_logging_req_seq_no
                                  ,p_response_status => log_status_code_success
                                  ,p_err_msg         => null
                                  ,p_sop_response    => p_response);
  
    bno76.log_sop_additional_to_ar(v_wrkshop_id_no
                                  ,v_cla_item_no
                                  ,w_logging_req_seq_no);
  
    utl_foundation.close_operation(p_input_token    => v_input_token
                                  ,p_service        => gc_package
                                  ,p_operation      => c_program
                                  ,p_svc_error_code => c_msg_id_other
                                  ,p_result         => p_result);
  
  exception
    when others then
      z_trace('DDN: sendoppdrag exception ' || sqlerrm || ' ' || sqlcode);
      if v_cursor%isopen
      then
        close v_cursor;
      end if;
    
      p_response := obj_dbs_send_oppdrag_response();
    
      err_msg := substr(sqlerrm
                       ,1
                       ,1000);
      dbs_trace('err_msg: ' || err_msg
               ,c_program);
    
      if p_response is null
      then
        p_response := obj_dbs_send_oppdrag_response();
      end if;
    
      set_decision(p_response
                  ,'9'
                  ,'90');
      p_response.return_text := substr(p_response.return_text ||
                                       ' ERROR_MESSAGE:' || err_msg
                                      ,1
                                      ,1000);
    
      begin
        create_error_case('NO33'
                         ,3
                         ,v_cla_case_no
                         ,err_msg);
      exception
        when others then
          err_msg                := substr(sqlerrm
                                          ,1
                                          ,1000);
          p_response.return_text := substr(p_response.return_text || ' ' ||
                                           err_msg
                                          ,1
                                          ,1000);
      end;
    
      bno74.log_sendoppdrag_response(p_request_seq_no  => w_logging_req_seq_no
                                    ,p_response_status => log_status_code_error
                                    ,p_err_msg         => err_msg
                                    ,p_sop_response    => p_response);
    
      bno76.log_sop_additional_to_ar(v_wrkshop_id_no
                                    ,v_cla_item_no
                                    ,w_logging_req_seq_no);
    
      if v_input_token is not null
         and nvl(v_input_token.commit_yn
                ,'Y') = 'Y'
      then
        commit;
      end if;
      utl_foundation.handle_service_exception(p_input_token    => v_input_token
                                             ,p_service        => gc_package
                                             ,p_operation      => c_program
                                             ,p_svc_error_code => c_msg_id_other
                                             ,p_result         => p_result);
  end sendoppdrag;

  --------------------------------------------------------------------------
    procedure sendstatus(p_input_token in obj_input_token,
                       p_request     in obj_dbs_send_status_request,
                       p_response    out nocopy obj_dbs_send_status_response,
                       p_result      out nocopy obj_result) is

    c_program constant varchar2(32) := 'sendStatus';
    v_input_token obj_input_token;
    w_logging_req_seq_no   number;
    c_msg_id_other     constant varchar2(17) := 'DBS-OPP-020-99999';

  begin
    
    trace_configuration;
    dbs_trace('START sendStatus', c_program);
  
    --call to uf_72_oppdrag_sendstatus
    bno72.uf_72_oppdrag_sendstatus(p_input_token => p_input_token,
                                   p_request     => p_request,
                                   p_response    => p_response,
                                   p_result      => p_result);
                                   
  end sendStatus;

end;
/
