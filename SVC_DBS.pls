CREATE OR REPLACE package svc_dbs is
  --------------------------------------------------------------------------
  -- Subject    : Common service utilities for DBS service
  -- File       : $Release: @releaseVersion@ $
  --              $Id: SVC_DBS.pls 71051 2016-11-09 13:40:09Z apr $
  -- Copyright (c) TIA Technology A/S 1998-2011. All rights reserved.
  --
  -- common / supportive / utility package for case service.
  --------------------------------------------------------------------------

  gc_package              constant varchar2(30) := 'svc_dbs';
  gc_area_code            constant varchar2(3) := 'DBS';
  log_status_code_success constant varchar2(10) := 'SUCCESS';
  log_status_code_error   constant varchar2(10) := 'ERROR';
  orgnr_verksted_dummy    constant varchar2(10) := '999999999';

  type skadenr_type is table of varchar2(50) index by binary_integer;

  type forsavtal_type is table of varchar2(50) index by binary_integer;

  type skdato_type is table of date index by binary_integer;

  type regnr_type is table of varchar2(50) index by binary_integer;

  type navn_type is table of varchar2(100) index by binary_integer;

  type item_type is table of varchar2(3) index by binary_integer;

  type currency_amt_type is table of number index by binary_integer;

  type seq_no_type is table of number index by binary_integer;

  type currency_code_type is table of varchar2(3) index by binary_integer;

  type receiver_id_no_type is table of number index by binary_integer;

  --------------------------------------------------------------------------
  -- This procedure process HentGlassSkadeDetaljer webservice.
  -- Returns information about cover of vehicle on incident date.
  --
  -- Parameters:
  --   p_input_token  Standard input token,
  --   p_hentglass_request  OOT representing request for hentGlassSkadeDetaljer
  --   p_hentglass_response OOT representing response from hentGlassSkadeDetaljer
  --   p_result       Standard result object type
  procedure hentglassskadedetaljer(p_input_token        in obj_input_token
                                  ,p_hentglass_request  in obj_dbs_hentglass_request
                                  ,p_hentglass_response out nocopy obj_dbs_hentglass_response
                                  ,p_result             out nocopy obj_result);

  --------------------------------------------------------------------------
  -- This procedure process HentKarosseriSkadeDetaljer webservice.
  -- Returns information about vehicle and insurer.
  --
  -- Parameters:
  --   p_input_token            Standard input token,
  --   p_hentkarosseri_request  OOT representing request for hentKarosseriSkadeDetaljer
  --   p_hentkarosseri_response OOT representing response from hentKarosseriSkadeDetaljer
  --   p_result                 Standard result object type
  procedure hentkarosseriskadedetaljer(p_input_token            in obj_input_token
                                      ,p_hentkarosseri_request  in obj_dbs_hentkarosseri_request
                                      ,p_hentkarosseri_response out nocopy obj_dbs_hentkarosseri_response
                                      ,p_result                 out nocopy obj_result);

  --------------------------------------------------------------------------
  -- This procedure process HentFakturagrunnlagStatus webservice.
  -- In request there is data with invoice.
  -- For glass Damage creates event and claim, checks additional rules and returns information about created claim.
  -- For general case checks if claim exists, checks if claim estime equals faktura amount and returns information
  -- if claim was accepted then returns additional information about excess, deductibles and information if car is subject to VAT.
  --
  -- Parameters:
  --   p_input_token            Standard input token,
  --   p_operation_request      OOT representing request for hentFakturagrunnlagStatus
  --   p_operation_response     OOT representing response from hentFakturagrunnlagStatus
  --   p_result                 Standard result object type
  procedure hentfakturagrunnlagstatus(p_input_token        in obj_input_token
                                     ,p_operation_request  in obj_dbs_operation_request
                                     ,p_operation_response out nocopy obj_dbs_operation_response
                                     ,p_result             out nocopy obj_result);

  --------------------------------------------------------------------------
  -- This procedure process SentFakturagrunnlag webservice.
  -- The service informs insurer that repair shop issues an invoice for insurer and customer.
  -- In response service creates payment, closes claim and prepares data for making payment via Telepay.
  --
  -- Parameters:
  --   p_input_token            Standard input token,
  --   p_operation_request      OOT representing request for sendFakturagrunnlag
  --   p_operation_response     OOT representing response from sendFakturagrunnlag
  --   p_result                 Standard result object type
  procedure sendfakturagrunnlag(p_input_token        in obj_input_token
                               ,p_operation_request  in obj_dbs_sfg_request
                               ,p_operation_response out nocopy obj_dbs_sfg_response
                               ,p_result             out nocopy obj_result);
                               
  function round_decimals(p_number number) return number;
  
    ------------------------------------------------------------------------------
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
                             ,p_val3        in varchar2 := null);
                             
  function check_locked_case(p_cla_case_no cla_case.cla_case_no%type)
    return number; 
  --------------------------------------------------------------------------
  -- This procedure handles logging for DBS and DBS-K
  --
  -- Parameters:
  --   p_trace_text            Text to log,
  --   p_program               Running program 
  procedure dbs_trace(p_trace_text varchar2
                     ,p_program    varchar2);
end;
/
CREATE OR REPLACE package body svc_dbs is
  --------------------------------------------------------------------------
  -- Subject    : Common service utilities for DBS service
  -- File       : $Release: @releaseVersion@ $
  --              $Id: SVC_DBS.pls 71051 2016-11-09 13:40:09Z apr $
  -- Copyright (c) TIA Technology A/S 1998-2011. All rights reserved.
  --
  -- common / supportive / utility package for case service.
  --------------------------------------------------------------------------
 
  ------------------------------------------------------------------------------
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
 
  ------------------------------------------------------------------------------
  function round_decimals(p_number number) return number
  
   is
    w_number number;
  
  begin
    z_program('round_decimals');
    z_trace('p_number:' || p_number);
  
    if x_site_preference('YNO_DBS_ROUND_NUMBERS') = 'Y'
    then
      w_number := round(p_number);
      z_trace('Rounding switched on, return value:' || w_number);
    else
      w_number := p_number;
      z_trace('Rounding switched off, return value:' || w_number);
    end if;
    return w_number;
  
  end;

  ------------------------------------------------------------------------------
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
  procedure hentglassskadedetaljer(p_input_token        in obj_input_token
                                  ,p_hentglass_request  in obj_dbs_hentglass_request
                                  ,p_hentglass_response out nocopy obj_dbs_hentglass_response
                                  ,p_result             out nocopy obj_result) is
    c_program          constant varchar2(32) := 'hentGlassSkadeDetaljer';
    c_operation_number constant varchar2(3) := '020';
    c_msg_id_other     constant varchar2(17) := 'DBS-DBS-020-99999';
    v_ws_name            varchar2(2000);
    v_ws_method          varchar2(2000);
    v_ws_flow            varchar2(2);
    v_ws_tag_name        varchar2(2000);
    v_ws_def_name        yno_dbs_mapping.ws_def_name%type;
    v_is_configurable    varchar2(1);
    v_tia_table_name     varchar2(2000);
    v_tia_column_name    varchar2(2000);
    v_add_condition      varchar2(32000);
    v_user_function      varchar2(1);
    v_user_function_name varchar2(2000);
    v_select_clause      varchar2(32000);
    v_from_clause        varchar2(32000);
    v_where_clause       varchar2(32000);
    v_query              varchar2(32000);
    v_temp_char          varchar2(32000);
    v_obj_seq_no         object.seq_no%type;
    v_policy_seq_no      policy.policy_seq_no%type;
    v_al_seq_no          agreement_line.agr_line_seq_no%type;
    v_name_id_no         name.id_no%type;
    v_cursor             sys_refcursor;
    err_msg              varchar2(100);
    v_agr_line_no        object.agr_line_no%type;
    v_logging_req_seq_no number;
    v_lock               varchar2(100);
    v_input_token        obj_input_token;
    v_result             obj_result;
    v_obj_claim          obj_claim;
    v_error_message      varchar2(2000);
    v_error_code         number;
    v_result_count       number;
    p_return_code        number;
    p_obj_claim_event    obj_claim_event;
    v_glass_risk_no      cla_case.risk_no%type;
    v_glass_subrisk_no   cla_case.subrisk_no%type;
  
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
    dbs_trace('START hentGlassSkadeDetaljer'
             ,c_program);
  
    bno74.log_hentglass_request(p_hentglass_request
                               ,v_logging_req_seq_no);

    bno73.gw_obj_hentglass_request := p_hentglass_request;
    bno72.gw_obj_hentglass_request := p_hentglass_request;
  
    --Perform operation
    --find party and policy:
    v_ws_name   := 'GlassKarosseriSkadeDetaljer';
    v_ws_method := 'HentGlassSkadeDetaljer';
  
    -----------------------------------------------------------------------------
    -- Process LicenceNumber - find policy, agreement line, object and name id --
    -----------------------------------------------------------------------------
  
    v_ws_flow     := 'RQ';
    v_ws_def_name := bno71.get_ws_definition(v_ws_name
                                            ,v_ws_method
                                            ,v_ws_flow);
    v_ws_tag_name := 'LicenceNumber';
  
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
        :v_temp_char := ' || v_user_function_name ||
                        '; end;'
        using out v_temp_char;
    else
      v_temp_char := p_hentglass_request.licencenumber;
    end if;
  
    v_select_clause := 'SELECT object.seq_no, object.agr_line_no, po.policy_seq_no, al.agr_line_seq_no, po.policy_holder_id';
    v_from_clause   := '
    FROM object object
    join object_in_agreement_line_view oalv on (object.seq_no = oalv.seq_no and object.agr_line_no = oalv.agr_line_no)
    join agreement_line al on al.agr_line_seq_no = oalv.agr_line_seq_no
    join policy po on po.policy_seq_no = al.policy_seq_no
    join name n on n.id_no = po.policy_holder_id';
  
    v_where_clause := 'WHERE al.cancel_code = 0
    and al.cover_start_date < al.cover_end_date
    and trunc(:skade_dato, ''DDD'') between al.cover_start_date and al.cover_end_date
    and po.policy_status = ''P''';
  
    v_where_clause := v_where_clause || ' AND ' ||
                      bno71.get_object_where_clause(v_ws_def_name
                                                   ,'LicenceNumber'
                                                   ,v_temp_char);
  
    if length(v_add_condition) is not null
    then
      v_where_clause := v_where_clause || ' AND ' || v_add_condition;
    end if;
  
    v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
               v_where_clause;
  
    dbs_trace('Executing query: ' || v_query
             ,c_program);
    open v_cursor for v_query
      using p_hentglass_request.damagedate;
    fetch v_cursor
      into v_obj_seq_no
          ,v_agr_line_no
          ,v_policy_seq_no
          ,v_al_seq_no
          ,v_name_id_no;
    close v_cursor;
  
    p_hentglass_response                            := obj_dbs_hentglass_response();
    p_hentglass_response.damageinfo                 := obj_dbs_hgsd_rs_damageinfo();
    p_hentglass_response.damageinfo.modelyear       := 0;
    p_hentglass_response.damageinfo.ownrisk         := 0;
    p_hentglass_response.damageinfo.ownerphone      := ' ';
    p_hentglass_response.damageinfo.ownername       := ' ';
    p_hentglass_response.damageinfo.owneraddress    := ' ';
    p_hentglass_response.damageinfo.ownerpostalcode := '0000';
    p_hentglass_response.damageinfo.ownerpostalarea := ' ';
    p_hentglass_response.damageinfo.insurancenumber := ' ';
    p_hentglass_response.damageinfo.objectname      := ' ';
    p_hentglass_response.damageinfo.licencenumber   := p_hentglass_request.licencenumber;
  
    ---------------------------------------------------------------------------
    -- Process ReturnCode                                                    --
    ---------------------------------------------------------------------------
    v_ws_flow     := 'RS';
    v_ws_def_name := bno71.get_ws_definition(v_ws_name
                                            ,v_ws_method
                                            ,v_ws_flow);
    v_ws_tag_name := 'ReturnCode';
  
    if p_hentglass_request.customerapproval = 0 --false
    then
      p_hentglass_response.returncode := 8;
    else
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
          :dekning := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.returncode, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_select_clause := 'select substr(object.' ||
                           bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                           ,v_ws_tag_name
                                                           ,v_obj_seq_no) ||
                           ', 1, 1)';
        v_from_clause   := 'from object';
        v_where_clause  := 'where object.seq_no = :v_obj_seq_no';
      
        if length(v_add_condition) is not null
        then
          v_where_clause := v_where_clause || ' AND ' || v_add_condition;
        end if;
      
        v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
                   v_where_clause;
      
        dbs_trace('Dekning - Executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_name_id_no;
        fetch v_cursor
          into p_hentglass_response.returncode;
        close v_cursor;
      
      end if;
    end if;
    dbs_trace('Dekning: ' || p_hentglass_response.returncode
             ,c_program);
  
    -----------------------------------------------------------------------------
    -- If returncode in (8)9 just prepare ReturnText                           --
    -----------------------------------------------------------------------------
    if p_hentglass_response.returncode = 1
    then
    
      ---------------------------------------------------------------------------
      -- Create response object                                                --
      ---------------------------------------------------------------------------
      v_glass_risk_no := bno72.uf_72_get_risk_no(c_program
                                                ,bno72.claim_type_glass
                                                ,bno72.claim_table_name
                                                ,v_al_seq_no);
      if v_glass_risk_no is null
      then
        create_error_case('NO09'
                         ,0
                         ,null
                         ,bno72.claim_type_glass
                         ,bno72.claim_table_name
                         ,v_al_seq_no);
      end if;
    
      v_glass_subrisk_no := bno72.uf_72_get_subrisk_no(c_program
                                                      ,bno72.claim_type_glass
                                                      ,bno72.claim_table_name
                                                      ,v_al_seq_no);
      if v_glass_subrisk_no is null
      then
        create_error_case('NO10'
                         ,0
                         ,null
                         ,bno72.claim_type_glass
                         ,bno72.claim_table_name
                         ,v_al_seq_no);
      end if;
    
      v_query := 'select count(cla_case.cla_case_no)';
      v_query := v_query || ' from cla_case cla_case';
      v_query := v_query ||
                 ' join cla_event cla_event on cla_case.cla_event_no = cla_event.cla_event_no';
      v_query := v_query ||
                 ' where trunc(cla_event.incident_date) = trunc(:w_param_skadedato)';
      v_query := v_query || ' and cla_case.object_seq_no = :object_seq_no';
      v_query := v_query ||
                 ' and cla_case.policy_line_seq_no = :policy_line_seq_no';
      v_query := v_query || ' and cla_case.risk_no = :v_risk_no';
    
      dbs_trace('Checking if there are claims. Executing query: ' ||
                v_query
               ,c_program);
      open v_cursor for v_query
        using p_hentglass_request.damagedate, v_obj_seq_no, v_al_seq_no, v_glass_risk_no;
      fetch v_cursor
        into v_result_count;
      close v_cursor;
      dbs_trace('Found existing claims: ' || v_result_count
               ,c_program);
    
      if v_result_count = 0
      then
        --Creating claim
        if v_agr_line_no is null
           or v_name_id_no is null
           or v_al_seq_no is null
           or v_obj_seq_no is null
        then
          v_error_code := 3;
          goto error_handler;
        end if;
      
        bno72.uf_72_gsd_pre_create_claim(p_hentglass_request
                                        ,v_name_id_no
                                        ,v_agr_line_no
                                        ,v_al_seq_no
                                        ,v_obj_seq_no
                                        ,p_return_code
                                        ,p_obj_claim_event
                                        ,v_result);
      
        if p_return_code = 0
        then
          v_lock                         := x_site_preference('YNO_DBS_CLAIM_LOCK');
          v_obj_claim                    := bno72.uf_72_gsd_new_claim_data(p_hentglass_request);
          v_obj_claim.policy_line_no     := v_agr_line_no;
          v_obj_claim.name_id_no         := v_name_id_no;
          v_obj_claim.policy_line_seq_no := v_al_seq_no;
          v_obj_claim.object_seq_no      := v_obj_seq_no;
          v_obj_claim.risk_no            := v_glass_risk_no;
          v_obj_claim.subrisk_no         := v_glass_subrisk_no;
        
          p_obj_claim_event        := bno72.uf_72_gsd_new_cla_event_data(p_hentglass_request);
          p_obj_claim_event.claims := tab_claim();
          p_obj_claim_event.claims.extend;
          p_obj_claim_event.claims(1) := v_obj_claim;
        
          dbs_trace('Creating claim'
                   ,c_program);
          svc_claim_atomic.createclaim(v_input_token
                                      ,p_obj_claim_event
                                      ,v_lock
                                      ,v_result);
        end if;
      
        if v_result.doeserrorexist
        then
          v_error_code := 4;
          for elem in 1 .. v_result.messages.count
          loop
            v_error_message := v_error_message || v_result.messages(elem)
                              .message_text || ',';
          end loop;
          goto error_handler;
        end if;
      
        bno72.uf_72_gsd_post_create_claim(p_hentglass_request
                                         ,v_name_id_no
                                         ,v_agr_line_no
                                         ,v_obj_seq_no
                                         ,p_obj_claim_event.claims(1)
                                          .claim_no
                                         ,p_obj_claim_event.event_no);
      
        p_hentglass_response.damageinfo.claimnumber := p_obj_claim_event.claims(1)
                                                       .claim_no;
        dbs_trace('Claim created, claim_no: ' ||
                  p_hentglass_response.damageinfo.claimnumber
                 ,c_program);
      elsif v_result_count = 1
      then
        v_query := 'select cla_case.cla_case_no';
        v_query := v_query || ' from cla_case cla_case';
        v_query := v_query ||
                   ' join cla_event cla_event on cla_case.cla_event_no = cla_event.cla_event_no';
        v_query := v_query ||
                   ' where trunc(cla_event.incident_date) = trunc(:w_param_skadedato)';
        v_query := v_query ||
                   ' and cla_case.object_seq_no = :object_seq_no';
        v_query := v_query ||
                   ' and cla_case.policy_line_seq_no = :policy_line_seq_no';
        v_query := v_query || ' and cla_case.risk_no = :v_risk_no';
      
        open v_cursor for v_query
          using p_hentglass_request.damagedate, v_obj_seq_no, v_al_seq_no, v_glass_risk_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.claimnumber;
        close v_cursor;
      elsif v_result_count > 1
      then
        v_error_code := 14;
        goto error_handler;
      end if;
    
      ---------------------------------------------------------------------------
      -- Process OwnerName                                                     --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'OwnerName';
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
        dbs_trace('Eiernamn - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :eiernamn := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.ownername, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_select_clause := 'SELECT substr(name.' || v_tia_column_name ||
                           ', 1, 25)';
        v_from_clause   := 'FROM name';
        v_where_clause  := 'WHERE id_no = :v_name_id_no';
      
        if length(v_add_condition) is not null
        then
          v_where_clause := v_where_clause || ' AND ' || v_add_condition;
        end if;
      
        v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
                   v_where_clause;
      
        dbs_trace('Eiernamn - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_name_id_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.ownername;
        close v_cursor;
      end if;
    
      p_hentglass_response.damageinfo.ownername := nvl(p_hentglass_response.damageinfo.ownername
                                                      ,' ');
    
      dbs_trace('Eiernamn: ' || p_hentglass_response.damageinfo.ownername
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process OwnerAddress                                                  --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'OwnerAddress';
    
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
        dbs_trace('Eieradress - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :eieradress := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.owneraddress, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_select_clause := 'SELECT substr(name.' || v_tia_column_name ||
                           ', 1, 25)';
        v_from_clause   := 'FROM name';
        v_where_clause  := 'WHERE id_no = :v_name_id_no';
      
        if length(v_add_condition) is not null
        then
          v_where_clause := v_where_clause || ' AND ' || v_add_condition;
        end if;
      
        v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
                   v_where_clause;
      
        dbs_trace('Eieradress - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_name_id_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.owneraddress;
        close v_cursor;
      end if;
    
      p_hentglass_response.damageinfo.owneraddress := nvl(p_hentglass_response.damageinfo.owneraddress
                                                         ,' ');
      dbs_trace('Eieradress: ' ||
                p_hentglass_response.damageinfo.owneraddress
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process OwnerPostalCode                                               --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'OwnerPostalCode';
    
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
        dbs_trace('Eierpostnr - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :eierpostnr := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.ownerpostalcode, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_query := 'SELECT substr(name.' || v_tia_column_name ||
                   ', 1, 4) as eierpostnr
        FROM name
        WHERE id_no = :id_no';
      
        if length(v_add_condition) is not null
        then
          v_query := v_query || ' AND ' || v_add_condition;
        end if;
      
        dbs_trace('Eierpostnr - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_name_id_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.ownerpostalcode;
        close v_cursor;
      end if;
    
      p_hentglass_response.damageinfo.ownerpostalcode := nvl(p_hentglass_response.damageinfo.ownerpostalcode
                                                            ,'0000');
    
      dbs_trace('Eierpostnr: ' ||
                p_hentglass_response.damageinfo.ownerpostalcode
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process OwnerPostalArea                                               --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'OwnerPostalArea';
    
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
        dbs_trace('Eierpoststed - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :eierpoststed := ' ||
                          v_user_function_name || '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.ownerpostalarea, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_query := 'SELECT substr(name.' || v_tia_column_name ||
                   ', 1, 25) as eierpoststed
        FROM name
        WHERE id_no = :id_no';
      
        if length(v_add_condition) is not null
        then
          v_query := v_query || ' AND ' || v_add_condition;
        end if;
      
        dbs_trace('Eierpoststed - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_name_id_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.ownerpostalarea;
        close v_cursor;
      end if;
    
      p_hentglass_response.damageinfo.ownerpostalarea := nvl(p_hentglass_response.damageinfo.ownerpostalarea
                                                            ,' ');
    
      dbs_trace('Eierpoststed: ' ||
                p_hentglass_response.damageinfo.ownerpostalarea
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process OwnerPhone                                                    --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'OwnerPhone';
    
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
        dbs_trace('Eiertel - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :eiertel := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.ownerphone, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_query := 'SELECT substr(name_telephone.' || v_tia_column_name ||
                   ', 1, 15) as eiertel
        FROM name_telephone
        WHERE name_id_no = :id_no';
      
        if length(v_add_condition) is not null
        then
          v_query := v_query || ' AND ' || v_add_condition;
        end if;
      
        dbs_trace('Eiertel - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_name_id_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.ownerphone;
        close v_cursor;
      end if;
      p_hentglass_response.damageinfo.ownerphone := nvl(substr(regexp_replace(p_hentglass_response.damageinfo.ownerphone
                                                                             ,'[^[:digit:]]'
                                                                             ,null)
                                                              ,1
                                                              ,15)
                                                       ,' ');
      dbs_trace('Eiertel: ' || p_hentglass_response.damageinfo.ownerphone
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process VATObliged                                                    --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'VATObliged';
    
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
        dbs_trace('Mva - executing user function ' || v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :mva := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.vatobliged, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_query := 'SELECT object.' ||
                   bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                   ,v_ws_tag_name
                                                   ,v_obj_seq_no) ||
                   ' as mva
        FROM object
        WHERE seq_no = :seq_no';
      
        if length(v_add_condition) is not null
        then
          v_query := v_query || ' AND ' || v_add_condition;
        end if;
      
        dbs_trace('Mva - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_obj_seq_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.vatobliged;
        close v_cursor;
      end if;
      dbs_trace('Mva: ' || p_hentglass_response.damageinfo.vatobliged
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process InsuranceNumber                                               --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'InsuranceNumber';
    
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
        dbs_trace('Forsavtal - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :forsavtal := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.insurancenumber, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_query := 'SELECT substr(policy.' || v_tia_column_name ||
                   ', 1, 15) as forsavtal
        FROM policy
        WHERE policy_seq_no = :policy_seq_no';
      
        if length(v_add_condition) is not null
        then
          v_query := v_query || ' AND ' || v_add_condition;
        end if;
      
        dbs_trace('Forsavtal - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_policy_seq_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.insurancenumber;
        close v_cursor;
      end if;
    
      p_hentglass_response.damageinfo.insurancenumber := nvl(p_hentglass_response.damageinfo.insurancenumber
                                                            ,' ');
    
      dbs_trace('Forsavtal: ' ||
                p_hentglass_response.damageinfo.insurancenumber
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process ObjectName                                                    --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'ObjectName';
    
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
        dbs_trace('Fabrikat - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :fabrikat := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.objectname, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_query := 'SELECT substr(object.' ||
                   bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                   ,v_ws_tag_name
                                                   ,v_obj_seq_no) ||
                   ', 1, 15) as fabrikat
        FROM object
        WHERE seq_no = :obj_seq_no';
      
        if length(v_add_condition) is not null
        then
          v_query := v_query || ' AND ' || v_add_condition;
        end if;
      
        dbs_trace('Fabrikat - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_obj_seq_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.objectname;
        close v_cursor;
      end if;
    
      p_hentglass_response.damageinfo.objectname := nvl(p_hentglass_response.damageinfo.objectname
                                                       ,' ');
    
      dbs_trace('Fabrikat: ' || p_hentglass_response.damageinfo.objectname
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process ModelYear                                                     --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'ModelYear';
    
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
        dbs_trace('Modell-aar - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :modell_arr := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.modelyear, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_query := 'SELECT substr(object.' ||
                   bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                   ,v_ws_tag_name
                                                   ,v_obj_seq_no) ||
                   ', 1, 4) as modell_aar
        FROM object
        WHERE seq_no = :obj_seq_no';
      
        if length(v_add_condition) is not null
        then
          v_query := v_query || ' AND ' || v_add_condition;
        end if;
      
        dbs_trace('Modell-aar - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_obj_seq_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.modelyear;
        close v_cursor;
      end if;
    
      p_hentglass_response.damageinfo.modelyear := nvl(p_hentglass_response.damageinfo.modelyear
                                                      ,0);
    
      dbs_trace('Modell-aar: ' ||
                p_hentglass_response.damageinfo.modelyear
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process RentalCar                                                     --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'RentalCar';
    
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
        dbs_trace('Leiebil-ant-dag - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :Leiebil_ant_dag := ' ||
                          v_user_function_name || '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.rentalcar, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_select_clause := 'SELECT object.' ||
                           bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                           ,v_ws_tag_name
                                                           ,v_obj_seq_no) ||
                           ' as leiebil';
        v_from_clause   := 'FROM object';
        v_where_clause  := 'WHERE seq_no = :v_obj_seq_no';
      
        if length(v_add_condition) is not null
        then
          v_where_clause := v_where_clause || ' AND ' || v_add_condition;
        end if;
      
        v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
                   v_where_clause;
      
        dbs_trace('Leiebil-ant-dag - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_obj_seq_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.rentalcar;
        close v_cursor;
      end if;
      dbs_trace('Leiebil-ant-dag: ' ||
                p_hentglass_response.damageinfo.rentalcar
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process OwnRisk                                                       --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'OwnRisk';
    
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
        dbs_trace('Egenandel - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :egenandel := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.ownrisk, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_select_clause := 'SELECT object.' ||
                           bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                           ,v_ws_tag_name
                                                           ,v_obj_seq_no) ||
                           ' as egenandel';
        v_from_clause   := 'FROM object';
        v_where_clause  := 'WHERE seq_no = :v_obj_seq_no';
      
        if length(v_add_condition) is not null
        then
          v_where_clause := v_where_clause || ' AND ' || v_add_condition;
        end if;
      
        v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
                   v_where_clause;
      
        dbs_trace('Egenandel - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_obj_seq_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.ownrisk;
        close v_cursor;
      end if;
    
      p_hentglass_response.damageinfo.ownrisk := nvl(round_decimals(p_hentglass_response.damageinfo.ownrisk)
                                                    ,0);
    
      dbs_trace('Egenandel: ' || p_hentglass_response.damageinfo.ownrisk
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process Reduction                                                     --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'Reduction';
    
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
        dbs_trace('Avkortbel - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :avkortbel := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.reduction, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_select_clause := 'SELECT object.' ||
                           bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                           ,v_ws_tag_name
                                                           ,v_obj_seq_no) ||
                           ' as avkortbel';
        v_from_clause   := 'FROM object';
        v_where_clause  := 'WHERE seq_no = :v_obj_seq_no';
      
        if length(v_add_condition) is not null
        then
          v_where_clause := v_where_clause || ' AND ' || v_add_condition;
        end if;
      
        v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
                   v_where_clause;
      
        dbs_trace('Avkortbel - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_obj_seq_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.reduction;
        close v_cursor;
      end if;
      dbs_trace('Avkortbel: ' || p_hentglass_response.damageinfo.reduction
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process ReductionPercent                                              --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'ReductionPercent';
    
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
        dbs_trace('Avkortpros - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :avkortpros := ' || v_user_function_name ||
                          '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.reductionpercent, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_select_clause := 'SELECT object.' ||
                           bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                           ,v_ws_tag_name
                                                           ,v_obj_seq_no) ||
                           ' as avkortpros';
        v_from_clause   := 'FROM object';
        v_where_clause  := 'WHERE seq_no = :v_obj_seq_no';
      
        if length(v_add_condition) is not null
        then
          v_where_clause := v_where_clause || ' AND ' || v_add_condition;
        end if;
      
        v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
                   v_where_clause;
      
        dbs_trace('Avkortpros - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_obj_seq_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.reductionpercent;
        close v_cursor;
      end if;
    
      dbs_trace('Avkortpros: ' ||
                p_hentglass_response.damageinfo.reductionpercent
               ,c_program);
    
      ---------------------------------------------------------------------------
      -- Process OwnRiskDeduction                                              --
      ---------------------------------------------------------------------------
      v_ws_tag_name := 'OwnRiskDeduction';
    
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
        dbs_trace('Oppa-egenandel - executing user function ' ||
                  v_user_function_name
                 ,c_program);
        execute immediate '
        begin
          :oppa_egenandel := ' ||
                          v_user_function_name || '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
        end;
      '
          using out p_hentglass_response.damageinfo.ownriskdeduction, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
      else
        v_select_clause := 'SELECT object.' ||
                           bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                           ,v_ws_tag_name
                                                           ,v_obj_seq_no) ||
                           ' as oppa';
        v_from_clause   := 'FROM object';
        v_where_clause  := 'WHERE seq_no = :v_obj_seq_no';
      
        if length(v_add_condition) is not null
        then
          v_where_clause := v_where_clause || ' AND ' || v_add_condition;
        end if;
      
        v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
                   v_where_clause;
      
        dbs_trace('Oppa-egenandel - executing query: ' || v_query
                 ,c_program);
        open v_cursor for v_query
          using v_obj_seq_no;
        fetch v_cursor
          into p_hentglass_response.damageinfo.ownriskdeduction;
        close v_cursor;
      end if;
      dbs_trace('Oppa-egenandel: ' ||
                p_hentglass_response.damageinfo.ownriskdeduction
               ,c_program);
    
    end if; -- p_hentglass_response.returncode = 1
  
    ---------------------------------------------------------------------------
    -- Process ReturnText                                                        --
    ---------------------------------------------------------------------------
    v_ws_tag_name := 'ReturnText';
  
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
      dbs_trace('ReturnText - executing user function ' ||
                v_user_function_name
               ,c_program);
      execute immediate '
      begin
        :ReturnText := ' || v_user_function_name ||
                        '(:v_obj_seq_no, :v_policy_seq_no, :v_al_seq_no, :v_name_id_no);
      end;
    '
        using out p_hentglass_response.returntext, in v_obj_seq_no, v_policy_seq_no, v_al_seq_no, v_name_id_no;
    else
      v_select_clause := 'SELECT substr(object.' ||
                         bno71.get_obj_column_name_seq_no(v_ws_def_name
                                                         ,v_ws_tag_name
                                                         ,v_obj_seq_no) ||
                         ', 1, 70) as returntext';
      v_from_clause   := 'FROM object';
      v_where_clause  := 'WHERE seq_no = :v_obj_seq_no';
    
      if length(v_add_condition) is not null
      then
        v_where_clause := v_where_clause || ' AND ' || v_add_condition;
      end if;
    
      v_query := v_select_clause || ' ' || v_from_clause || ' ' ||
                 v_where_clause;
    
      dbs_trace('ReturnText - executing query: ' || v_query
               ,c_program);
      open v_cursor for v_query
        using v_obj_seq_no;
      fetch v_cursor
        into p_hentglass_response.returntext;
      close v_cursor;
    end if;
    dbs_trace('Returntext: ' || p_hentglass_response.returntext
             ,c_program);
  
    <<error_handler>>
    if v_error_code is not null
    then
      if v_error_message is null
      then
        v_error_message := x_reference2('YNO_DBS_ERROR_CODE'
                                       ,v_error_code
                                       ,'desc');
      else
        v_error_message := x_reference2('YNO_DBS_ERROR_CODE'
                                       ,v_error_code
                                       ,'desc') || ':' || v_error_message;
      end if;
      create_error_case('NO22'
                       ,2
                       ,p_hentglass_response.damageinfo.claimnumber
                       ,v_error_message);
    
      p_hentglass_response.returntext := substr(v_error_message
                                               ,1
                                               ,1000);
    
    end if;
  
    bno72.uf_72_gsd_pre_send_response(p_hentglass_request
                                     ,p_hentglass_response);
  
    bno74.log_hentglass_response(p_request_seq_no     => v_logging_req_seq_no
                                ,p_response_status    => log_status_code_success
                                ,p_err_msg            => null
                                ,p_hentglass_response => p_hentglass_response);
  
    -- Close operation
    utl_foundation.close_operation(p_input_token    => v_input_token
                                  ,p_service        => gc_package
                                  ,p_operation      => c_program
                                  ,p_svc_error_code => c_msg_id_other
                                  ,p_result         => p_result);
    p0000.trace_level := 0;
  exception
    when others then
      if v_cursor%isopen
      then
        close v_cursor;
      end if;
      p_hentglass_response := obj_dbs_hentglass_response();
    
      err_msg := substr(sqlerrm
                       ,1
                       ,1000);
    
      p_hentglass_response.returncode := 9;
      p_hentglass_response.returntext := substr(p_hentglass_response.returntext ||
                                                ' ERROR_MESSAGE:' ||
                                                err_msg
                                               ,1
                                               ,1000);
      begin
        create_error_case('NO32'
                         ,3
                         ,p_hentglass_response.damageinfo.claimnumber
                         ,err_msg);
      exception
        when others then
          err_msg                         := substr(sqlerrm
                                                   ,1
                                                   ,1000);
          p_hentglass_response.returntext := substr(p_hentglass_response.returntext || ' ' ||
                                                    err_msg
                                                   ,1
                                                   ,1000);
        
      end;
    
      bno74.log_hentglass_response(p_request_seq_no     => v_logging_req_seq_no
                                  ,p_response_status    => log_status_code_error
                                  ,p_err_msg            => err_msg
                                  ,p_hentglass_response => p_hentglass_response);
    
      utl_foundation.handle_service_exception(p_input_token    => v_input_token
                                             ,p_service        => gc_package
                                             ,p_operation      => c_program
                                             ,p_svc_error_code => c_msg_id_other
                                             ,p_result         => p_result);
  end hentglassskadedetaljer;

  --------------------------------------------------------------------------------------------
  procedure hentkarosseriskadedetaljer(p_input_token            in obj_input_token
                                      ,p_hentkarosseri_request  in obj_dbs_hentkarosseri_request
                                      ,p_hentkarosseri_response out nocopy obj_dbs_hentkarosseri_response
                                      ,p_result                 out nocopy obj_result) is
    c_program          constant varchar2(32) := 'hentKarosseriSkadeDetaljer';
    c_operation_number constant varchar2(3) := '010';
    c_msg_id_other     constant varchar2(17) := 'DBS-DBS-010-99999';
    err_msg               varchar2(100);
    c_cursor              sys_refcursor;
    w_ws_name             varchar2(100);
    w_ws_method           varchar2(100);
    w_ws_def_name         varchar2(20);
    w_ws_tag_name         varchar2(50);
    w_is_configurable     varchar2(1);
    w_tia_table_name      varchar2(50);
    w_tia_column_name     varchar2(50);
    w_add_condition       varchar2(2000);
    w_user_function       varchar2(1);
    w_user_function_name  varchar2(100);
    w_param_regnr         varchar2(100);
    w_param_skadenr       varchar2(100);
    w_param_forsavtal     varchar2(100);
    w_query               varchar2(32000);
    w_select              varchar2(32000);
    w_from                varchar2(32000);
    w_where               varchar2(32000);
    w_order               varchar2(32000);
    w_tp_from             varchar2(32000);
    w_tp_where            varchar2(32000);
    w_ntp_where           varchar2(32000);
    w_temp                varchar2(32000);
    w_regnr               varchar2(100);
    w_modellar            varchar2(100);
    w_objekt              varchar2(100);
    w_fordonsgrupp        varchar2(100);
    w_eiernamn            varchar2(100);
    w_eiertel             varchar2(100);
    w_forstagnamn         varchar2(100);
    w_forstagregnr        varchar2(100);
    w_sbid                varchar2(100);
    w_skadetyp            varchar2(100);
    w_forsavtal           varchar2(100);
    w_kmstand             varchar2(100);
    w_skadedatum          date;
    w_param_skadedatum    date;
    w_result_count        number;
    w_returkod            number;
    w_logging_req_seq_no  number;
    w_third_party_flag    number := 0;
    w_tp_result_count     number := 0;
    w_tp_know_reg_no_flag number := 0;
    w_skadenr_list        skadenr_type;
    w_forsavtal_list      forsavtal_type;
    w_skdato_list         skdato_type;
    w_regnr_list          regnr_type;
    w_navn_list           navn_type;
    w_tp_regnr_list       regnr_type;
    w_tp_navn_list        navn_type;
  
    cursor c_yno_dbs_ws_definition(p_ws_flow varchar2) is
      select ws_def_name
        from yno_dbs_ws_definition
       where ws_name = w_ws_name
         and ws_method = w_ws_method
         and flow = p_ws_flow;
  
    v_input_token obj_input_token;
  begin
    -- Initialize everything
    v_input_token         := obj_input_token();
    v_input_token.user_id := x_site_preference('YNO_DBS_CLAIM_USER_ID');
  
    utl_foundation.init_operation(p_input_token => v_input_token
                                 ,p_service     => gc_package
                                 ,p_operation   => c_program);
  
    trace_configuration;
    dbs_trace('START hentKarosseriSkadeDetaljer'
             ,c_program);
  
    bno74.log_hentkarosseri_request(p_hentkarosseri_request
                                   ,w_logging_req_seq_no);
  
    bno73.gw_obj_hentkarosseri_request := p_hentkarosseri_request;
    bno72.gw_obj_hentkarosseri_request := p_hentkarosseri_request;
    w_ws_name                          := 'GlassKarosseriSkadeDetaljer';
    w_ws_method                        := 'HentKarosseriSkadeDetaljer';
  
    open c_yno_dbs_ws_definition('RQ');
    fetch c_yno_dbs_ws_definition
      into w_ws_def_name;
    close c_yno_dbs_ws_definition;
  
    ---------------------------------------------------------------------------
    -- Process Request with parameters                                       --
    --    LicenceNumber     (object.xxx)
    --    ClaimNumber       (cla_case.cla_case_no)
    --    DamageDate        (cla_event.incident_date)
    --    InsuranceNumber   (policy.policy_no)
    --    CustomerApproval
    --    Alarm             it hasn't impact on service
    --    Mileage           it hasn't impact on service
    ---------------------------------------------------------------------------
    if p_hentkarosseri_request.licencenumber is not null
    then
      w_ws_tag_name := 'LicenceNumber';
      bno71.get_mapping_details(w_ws_def_name
                               ,w_ws_tag_name
                               ,w_is_configurable
                               ,w_tia_table_name
                               ,w_tia_column_name
                               ,w_add_condition
                               ,w_user_function
                               ,w_user_function_name);
      if w_user_function = 'Y'
      then
        execute immediate 'begin :v_param_value := ' ||
                          w_user_function_name || '; end;'
          using out w_param_regnr;
      else
        w_param_regnr := p_hentkarosseri_request.licencenumber;
      end if;
    end if;
  
    if p_hentkarosseri_request.claimnumber is not null
    then
      w_ws_tag_name := 'ClaimNumber';
      bno71.get_mapping_details(w_ws_def_name
                               ,w_ws_tag_name
                               ,w_is_configurable
                               ,w_tia_table_name
                               ,w_tia_column_name
                               ,w_add_condition
                               ,w_user_function
                               ,w_user_function_name);
      if w_user_function = 'Y'
      then
        execute immediate 'begin :v_param_value := ' ||
                          w_user_function_name || '; end;'
          using out w_param_skadenr;
      else
        w_param_skadenr := p_hentkarosseri_request.claimnumber;
      end if;
    end if;
  
    if p_hentkarosseri_request.damagedate is not null
    then
      w_ws_tag_name := 'DamageDate';
      bno71.get_mapping_details(w_ws_def_name
                               ,w_ws_tag_name
                               ,w_is_configurable
                               ,w_tia_table_name
                               ,w_tia_column_name
                               ,w_add_condition
                               ,w_user_function
                               ,w_user_function_name);
      if w_user_function = 'Y'
      then
        execute immediate 'begin :v_param_value := ' ||
                          w_user_function_name || '; end;'
          using out w_param_skadedatum;
      else
        w_param_skadedatum := p_hentkarosseri_request.damagedate;
      end if;
    end if;
  
    if p_hentkarosseri_request.insurancenumber is not null
    then
      w_ws_tag_name := 'InsuranceNumber';
      bno71.get_mapping_details(w_ws_def_name
                               ,w_ws_tag_name
                               ,w_is_configurable
                               ,w_tia_table_name
                               ,w_tia_column_name
                               ,w_add_condition
                               ,w_user_function
                               ,w_user_function_name);
      if w_user_function = 'Y'
      then
        execute immediate 'begin :v_param_value := ' ||
                          w_user_function_name || '; end;'
          using out w_param_forsavtal;
      else
        w_param_forsavtal := p_hentkarosseri_request.insurancenumber;
      end if;
    end if;
  
    ---------------------------------------------------------------------------
    -- Create response object                                                --
    ---------------------------------------------------------------------------
    p_hentkarosseri_response                                       := obj_dbs_hentkarosseri_response();
    p_hentkarosseri_response.singledamageinfo                      := obj_dbs_output();
    p_hentkarosseri_response.singledamageinfo.modelyear            := 0;
    p_hentkarosseri_response.singledamageinfo.protectmodelyear     := 0;
    p_hentkarosseri_response.singledamageinfo.vehicletypeid        := 0;
    p_hentkarosseri_response.singledamageinfo.protectvehicletypeid := 0;
    p_hentkarosseri_response.singledamageinfo.protectclaimnumber   := 0;
    p_hentkarosseri_response.singledamageinfo.damagedate           := to_date('01011900'
                                                                             ,'ddmmyyyy');
    p_hentkarosseri_response.singledamageinfo.protectdamagedate    := 0;
    p_hentkarosseri_response.singledamageinfo.protectownername     := 0;
    p_hentkarosseri_response.singledamageinfo.protectownerphone    := 0;
    p_hentkarosseri_response.singledamageinfo.damagetypeid         := 0;
    p_hentkarosseri_response.singledamageinfo.protectdamagetypeid  := 0;
    p_hentkarosseri_response.singledamageinfo.ownername            := ' ';
    p_hentkarosseri_response.singledamageinfo.ownerphone           := ' ';
    p_hentkarosseri_response.singledamageinfo.claimnumber          := p_hentkarosseri_request.claimnumber;
  
    if bno72.uf_72_hksd_val_request_data(p_hentkarosseri_request) = 2
    then
      w_returkod := 3;
      goto end_main;
    end if;
  
    if upper(nvl(p_hentkarosseri_request.customerapproval
                ,1)) = 0
    then
      -- customer  hasn't consented to obtain information from insurance
      w_returkod := 3;
      goto end_main;
    end if;
  
    open c_yno_dbs_ws_definition('RS');
    fetch c_yno_dbs_ws_definition
      into w_ws_def_name;
    close c_yno_dbs_ws_definition;
  
    w_select := 'select count(distinct(cla_case.cla_case_no))';
    w_from   := ' from cla_case cla_case
      join cla_event cla_event on cla_case.cla_event_no = cla_event.cla_event_no
      join policy_line policy_line on cla_case.policy_line_seq_no = policy_line.agr_line_seq_no
      join policy policy on policy_line.policy_seq_no = policy.policy_seq_no
      join object object on cla_case.object_seq_no = object.seq_no
      left join cla_third_party cla_third_party on cla_case.cla_case_no = cla_third_party.cla_case_no ';
    w_where  := '';
  
    if w_param_skadenr is not null
    then
      w_where := 'where cla_case.cla_case_no = ''' || w_param_skadenr || '''';
      -- additional check reg no with known claim number
      if w_param_regnr is not null
      then
        w_where := w_where || ' and (' ||
                   bno71.get_object_where_clause(w_ws_def_name
                                                ,'LicenceNumber'
                                                ,w_param_regnr) || ')';
      end if;
    else
      if w_param_regnr is not null
      then
        w_where := 'where (' ||
                   bno71.get_object_where_clause(w_ws_def_name
                                                ,'LicenceNumber'
                                                ,w_param_regnr) || ')';
      end if;
      if w_param_forsavtal is not null
      then
        if instr(w_where
                ,'where') > 0
        then
          w_where := w_where || ' and ';
        else
          w_where := 'where ';
        end if;
        w_where := w_where || 'policy.policy_no = ''' || w_param_forsavtal || '''';
      end if;
    
      if w_param_skadedatum is not null
      then
        if instr(w_where
                ,'where') > 0
        then
          w_where := w_where || ' and ';
        else
          w_where := 'where ';
        end if;
        w_where := w_where ||
                   'to_char(cla_event.incident_date, ''DDMMYYYY'') = ' ||
                   to_char(w_param_skadedatum
                          ,'DDMMYYYY');
      end if;
    end if;
  
    w_temp := bno72.uf_72_get_where_for_risk(bno72.claim_type_general);
    if w_temp is not null
    then
      if instr(w_where
              ,'where') > 0
      then
        w_where := w_where || ' and ' || w_temp;
      else
        w_where := 'where ' || w_temp;
      end if;
    end if;
    w_query     := w_select || w_from || w_where;
    w_ntp_where := w_where;
    dbs_trace('Executing query: ' || w_query
             ,c_program);
    dbs_trace('the rest: ' || substr(w_query
                                    ,1500
                                    ,1000)
             ,c_program);
  
    execute immediate w_query
      into w_result_count;
    dbs_trace('Number of claims without third_party: ' || w_result_count
             ,c_program);
  
    --3rd party (checking if there is claim for third party)
    w_tp_from  := ' from cla_case cla_case
    join cla_event cla_event on cla_case.cla_event_no = cla_event.cla_event_no
    join policy_line policy_line on cla_case.policy_line_seq_no = policy_line.agr_line_seq_no
    join policy policy on policy_line.policy_seq_no = policy.policy_seq_no
      join object object on cla_case.object_seq_no = object.seq_no
      join cla_third_party cla_third_party on cla_case.cla_case_no = cla_third_party.cla_case_no ';
    w_tp_where := '';
    if w_param_skadenr is not null
    then
      w_tp_where := 'where cla_case.cla_case_no = ''' || w_param_skadenr || '''';
      -- additional check reg no with known claim number
      if w_param_regnr is not null
      then
        w_tp_where := w_tp_where || ' and cla_third_party.' ||
                      bno72.uf_72_third_party_reg_col || '= ''' ||
                      w_param_regnr || '''';
      end if;
    else
      if w_param_regnr is not null
      then
        w_tp_where := 'where  cla_third_party.' ||
                      bno72.uf_72_third_party_reg_col || '= ''' ||
                      w_param_regnr || '''';
      end if;
      if w_param_forsavtal is not null
      then
        if instr(w_tp_where
                ,'where') > 0
        then
          w_tp_where := w_tp_where || ' and ';
        else
          w_tp_where := 'where ';
        end if;
        w_tp_where := w_tp_where || 'policy.policy_no = ''' ||
                      w_param_forsavtal || '''';
      end if;
    
      if w_param_skadedatum is not null
      then
        if instr(w_tp_where
                ,'where') > 0
        then
          w_tp_where := w_tp_where || ' and ';
        else
          w_tp_where := 'where ';
        end if;
        w_tp_where := w_tp_where ||
                      'to_char(cla_event.incident_date, ''DDMMYYYY'') = ' ||
                      to_char(w_param_skadedatum
                             ,'DDMMYYYY');
      end if;
    end if;
  
    w_temp := bno72.uf_72_get_where_for_risk(bno72.claim_type_general);
    if w_temp is not null
    then
      if instr(w_where
              ,'where') > 0
      then
        w_where := w_where || ' and ' || w_temp;
      else
        w_where := 'where ' || w_temp;
      end if;
    end if;
    w_select := 'select count(distinct(cla_case.cla_case_no))';
    w_query  := w_select || w_tp_from || w_tp_where;
  
    dbs_trace('Executing query for third_party: ' || w_query
             ,c_program);
    execute immediate w_query
      into w_tp_result_count;
    dbs_trace('Number of claims with third_party: ' || w_result_count
             ,c_program);
  
    if w_tp_result_count > 0
       and w_result_count = 0
    then
      w_third_party_flag := 1;
    end if;
  
    --checking if for third party the regno is known
    if w_third_party_flag = 1
       and p_hentkarosseri_request.licencenumber is not null
    then
      w_tp_know_reg_no_flag := 1;
    end if;
  
    if w_result_count = 0
    then
      w_result_count := w_tp_result_count;
    end if;
  
    dbs_trace('Found claims: ' || w_result_count
             ,c_program);
  
    if w_result_count = 0
    then
      w_returkod := 3;
      goto end_main;
    elsif w_result_count = 1
    then
      w_returkod := 1;
      goto output;
    elsif w_result_count between 2 and 15
    then
      w_returkod := 2;
      goto output;
    elsif w_result_count > 15
    then
      w_returkod := 4;
      goto end_main;
    end if;
  
    <<output_liste>>
    w_ws_def_name := bno71.get_ws_definition(w_ws_name
                                            ,w_ws_method
                                            ,'RS');
  
    --ORDER of values: skadenr, skdato, polisenr, regnr, navn
    w_select := 'select cla_case.cla_case_no, cla_event.incident_date, policy.policy_no, cla_third_party.' ||
                bno72.uf_72_third_party_reg_col;
    w_from   := ' from cla_case cla_case
    join cla_event cla_event on cla_case.cla_event_no = cla_event.cla_event_no
    join name name on cla_case.name_id_no = name.id_no
    join policy_line policy_line on cla_case.policy_line_seq_no = policy_line.agr_line_seq_no
    join policy policy on policy_line.policy_seq_no = policy.policy_seq_no
    join object object on cla_case.object_seq_no = object.seq_no
    left join cla_third_party cla_third_party on cla_case.cla_case_no = cla_third_party.cla_case_no
    left join name name_tp on cla_third_party.name_id_no = name_tp.id_no ';
  
    bno71.get_mapping_details(w_ws_def_name
                             ,'DamageInfoList.LicenceNumber'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
    w_select := w_select || ', ' || w_tia_table_name || '.' ||
                bno71.get_obj_column_name_claim_no(w_ws_def_name
                                                  ,'DamageInfoList.LicenceNumber'
                                                  ,w_param_skadenr);
  
    bno71.get_mapping_details(w_ws_def_name
                             ,'DamageInfoList.OwnerName'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
    w_select := w_select || ', ' || w_tia_table_name || '.' ||
                w_tia_column_name;
    w_select := w_select || ', ' || 'name_tp' || '.' || w_tia_column_name;
  
    if w_third_party_flag = 0
    then
      w_query := w_select || w_from || w_ntp_where;
    else
      w_query := w_select || w_from || w_tp_where;
    end if;
    dbs_trace('Building output_liste, query: ' || w_query
             ,c_program);
    execute immediate w_query bulk collect
      into w_skadenr_list, w_skdato_list, w_forsavtal_list, w_tp_regnr_list, w_regnr_list, w_navn_list, w_tp_navn_list;
  
    p_hentkarosseri_response.damageinfolist := tab_dbs_output_liste();
  
    for elem in 1 .. w_skadenr_list.count
    loop
      exit when elem > 15;
      p_hentkarosseri_response.damageinfolist.extend;
      p_hentkarosseri_response.damageinfolist(elem) := obj_dbs_output_liste();
      p_hentkarosseri_response.damageinfolist(elem).damageinfo := obj_dbs_hksd_rs_damageinfo();
      p_hentkarosseri_response.damageinfolist(elem).damageinfo.claimnumber := w_skadenr_list(elem);
      p_hentkarosseri_response.damageinfolist(elem).damageinfo.damagedate := nvl(w_skdato_list(elem)
                                                                                ,to_date('01011900'
                                                                                        ,'ddmmyyyy'));
      p_hentkarosseri_response.damageinfolist(elem).damageinfo.insurancenumber := substr(to_char(w_forsavtal_list(elem))
                                                                                        ,1
                                                                                        ,15);
      if w_tp_regnr_list(elem) is not null
      then
        p_hentkarosseri_response.damageinfolist(elem).damageinfo.licencenumber := substr(w_tp_regnr_list(elem)
                                                                                        ,1
                                                                                        ,7);
        p_hentkarosseri_response.damageinfolist(elem).damageinfo.ownername := nvl(substr(w_tp_navn_list(elem)
                                                                                        ,1
                                                                                        ,25)
                                                                                 ,' ');
      else
        p_hentkarosseri_response.damageinfolist(elem).damageinfo.licencenumber := substr(w_regnr_list(elem)
                                                                                        ,1
                                                                                        ,7);
        p_hentkarosseri_response.damageinfolist(elem).damageinfo.ownername := nvl(substr(w_navn_list(elem)
                                                                                        ,1
                                                                                        ,25)
                                                                                 ,' ');
      end if;
    end loop;
  
    goto end_main;
  
    <<output>>
    if w_param_skadenr is null
    then
      w_select := 'select cla_case.cla_case_no';
      w_order  := ' order by cla_case.cla_case_no desc';
      if w_third_party_flag = 0
      then
        w_query := w_select || w_from || w_where || w_order;
      else
        w_query := w_select || w_tp_from || w_tp_where || w_order;
      end if;
      open c_cursor for w_query;
      fetch c_cursor
        into w_param_skadenr;
      close c_cursor;
    end if;
  
    bno73.gw_obj_hentkarosseri_request.claimnumber := w_param_skadenr;
    bno72.gw_obj_hentkarosseri_request.claimnumber := w_param_skadenr;
  
    w_ws_def_name := bno71.get_ws_definition(w_ws_name
                                            ,w_ws_method
                                            ,'RS');
    ------------------------------------------------------------------------------
    -- Response param 'LicenceNumber'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'LicenceNumber'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Regnr - executing user function ' || w_user_function_name
               ,c_program);
      execute immediate 'begin :Regnr := ' || w_user_function_name ||
                        '; end;'
        using out w_regnr;
    else
      if w_third_party_flag = 0
      then
        w_select := 'select ' || w_tia_table_name || '.' ||
                    bno71.get_obj_column_name_claim_no(w_ws_def_name
                                                      ,'LicenceNumber'
                                                      ,w_param_skadenr);
        w_from   := ' from policy_line pl, object object, cla_case cla_case ';
        w_where  := 'where object.suc_seq_no is null';
        w_where  := w_where || ' and pl.suc_seq_no is null';
        w_where  := w_where ||
                    ' and cla_case.policy_line_no = object.agr_line_no';
        w_where  := w_where || ' and pl.agr_line_no = object.agr_line_no';
        w_where  := w_where ||
                    ' and cla_case.cla_case_no = :w_param_skadenr';
      
        if w_add_condition is not null
        then
          w_where := w_where || ' and ' || w_add_condition;
        end if;
      else
        w_select := 'select ' || bno72.uf_72_third_party_reg_col;
        w_from   := ' from cla_third_party';
        w_where  := ' where cla_case_no = :w_param_skadenr';
      end if;
      w_query := w_select || w_from || w_where;
      if w_tp_know_reg_no_flag = 1
      then
        dbs_trace('Given regno from request: ' || w_param_regnr
                 ,c_program);
        w_regnr := w_param_regnr;
      else
        dbs_trace('Regnr - executing query: ' || w_query
                 ,c_program);
        open c_cursor for w_query
          using w_param_skadenr;
        fetch c_cursor
          into w_regnr;
        close c_cursor;
      end if;
    end if;
    p_hentkarosseri_response.singledamageinfo.licencenumber := substr(w_regnr
                                                                     ,1
                                                                     ,7);
    dbs_trace('Regnr: ' ||
              p_hentkarosseri_response.singledamageinfo.licencenumber
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'ObjectName'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'ObjectName'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Objekt - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Objekt := ' || w_user_function_name ||
                        '; end;'
        using out w_objekt;
    else
      w_select := 'select ' || w_tia_table_name || '.' ||
                  bno71.get_obj_column_name_claim_no(w_ws_def_name
                                                    ,'ObjectName'
                                                    ,w_param_skadenr);
      w_from   := ' from cla_case cla_case
                join object object on cla_case.policy_line_no = object.agr_line_no ';
      w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
    
      dbs_trace('Objekt - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_objekt;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.objectname := substr(w_objekt
                                                                  ,1
                                                                  ,15);
    dbs_trace('Objekt: ' ||
              p_hentkarosseri_response.singledamageinfo.objectname
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'ModelYear'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'ModelYear'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Modellar - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Modellar := ' || w_user_function_name ||
                        '; end;'
        using out w_modellar;
    else
      w_select := 'select ' || w_tia_table_name || '.' ||
                  bno71.get_obj_column_name_claim_no(w_ws_def_name
                                                    ,'ModelYear'
                                                    ,w_param_skadenr);
      w_from   := ' from cla_case cla_case
                join object object on cla_case.policy_line_no = object.agr_line_no ';
      w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
    
      dbs_trace('Modellar - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_modellar;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.modelyear := nvl(substr(w_modellar
                                                                     ,1
                                                                     ,4)
                                                              ,0);
    dbs_trace('Modellar: ' ||
              p_hentkarosseri_response.singledamageinfo.modelyear
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'VechicleTypeId'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'VechicleTypeId'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Fordonsgrupp - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Fordonsgrupp := ' || w_user_function_name ||
                        '; end;'
        using out w_fordonsgrupp;
    else
      w_select := 'select ' || w_tia_table_name || '.' ||
                  bno71.get_obj_column_name_claim_no(w_ws_def_name
                                                    ,'VechicleTypeId'
                                                    ,w_param_skadenr);
      w_from   := ' from cla_case cla_case
                join object object on cla_case.policy_line_no = object.agr_line_no ';
      w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
    
      dbs_trace('Fordonsgrupp - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_fordonsgrupp;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.vehicletypeid := nvl(substr(w_fordonsgrupp
                                                                         ,1
                                                                         ,2)
                                                                  ,0);
    dbs_trace('Fordonsgrupp: ' ||
              p_hentkarosseri_response.singledamageinfo.vehicletypeid
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'InsuranceNumber'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'InsuranceNumber'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Forsavtal - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Forsavtal := ' || w_user_function_name ||
                        '; end;'
        using out w_forsavtal;
    else
      w_select := 'select ' || w_tia_table_name || '.' || w_tia_column_name;
      w_from   := ' from cla_case cla_case
                join policy_line policy_line on cla_case.policy_line_seq_no = policy_line.agr_line_seq_no
                join policy policy on policy_line.policy_no = policy.policy_no ';
      w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
    
      dbs_trace('Forsavtal - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_forsavtal;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.insurancenumber := substr(w_forsavtal
                                                                       ,1
                                                                       ,15);
    dbs_trace('Forsavtal: ' ||
              p_hentkarosseri_response.singledamageinfo.insurancenumber
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'DamageDate'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'DamageDate'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Skadedatum - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Skadedatum := ' || w_user_function_name ||
                        '; end;'
        using out w_skadedatum;
    else
      w_select := 'select ' || w_tia_table_name || '.' || w_tia_column_name;
      w_from   := ' from cla_case cla_case
                join cla_event cla_event on cla_case.cla_event_no = cla_event.cla_event_no ';
      w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
    
      dbs_trace('Skadedatum - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_skadedatum;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.damagedate := nvl(w_skadedatum
                                                               ,to_date('01011900'
                                                                       ,'ddmmyyyy'));
    dbs_trace('Skadedatum: ' ||
              p_hentkarosseri_response.singledamageinfo.damagedate
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'OwnerName'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'OwnerName'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Eiernamn - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Eiernamn := ' || w_user_function_name ||
                        '; end;'
        using out w_eiernamn;
    else
      if w_third_party_flag = 0
      then
        w_select := 'select ' || w_tia_table_name || '.' ||
                    w_tia_column_name;
        w_from   := ' from cla_case cla_case
                join name name on cla_case.name_id_no = name.id_no ';
        w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
      
        if w_add_condition is not null
        then
          w_where := w_where || ' and ' || w_add_condition;
        end if;
      else
        w_select := 'select ' || w_tia_table_name || '.' ||
                    w_tia_column_name;
        w_from   := ' from cla_third_party cla_third_party
                  join name name on cla_third_party.name_id_no = name.id_no ';
        w_where  := 'where cla_third_party.cla_case_no = :w_param_skadenr';
        --using given third party regno
        if w_tp_know_reg_no_flag = 1
        then
          w_where := w_where || ' and cla_third_party.' ||
                     bno72.uf_72_third_party_reg_col || '= ''' ||
                     w_param_regnr || '''';
        end if;
      end if;
      w_query := w_select || w_from || w_where;
      dbs_trace('Eiernamn - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_eiernamn;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.ownername := nvl(substr(w_eiernamn
                                                                     ,1
                                                                     ,25)
                                                              ,' ');
    dbs_trace('Eiernamn: ' ||
              p_hentkarosseri_response.singledamageinfo.ownername
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'OwnerPhone'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'OwnerPhone'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Eiertel - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Eiertel := ' || w_user_function_name ||
                        '; end;'
        using out w_eiertel;
    else
      if w_third_party_flag = 0
      then
        w_select := 'select ' || w_tia_table_name || '.' ||
                    w_tia_column_name;
        w_from   := ' from cla_case cla_case
                join name name on cla_case.name_id_no = name.id_no
                left join name_telephone name_telephone on name.id_no = name_telephone.name_id_no ';
        w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
      
        if w_add_condition is not null
        then
          w_where := w_where || ' and ' || w_add_condition;
        end if;
      else
        w_select := 'select ' || w_tia_table_name || '.' ||
                    w_tia_column_name;
        w_from   := ' from cla_third_party cla_third_party
                  join name name on cla_third_party.name_id_no = name.id_no
                  left join name_telephone name_telephone on name.id_no = name_telephone.name_id_no ';
        w_where  := 'where cla_third_party.cla_case_no = :w_param_skadenr';
      end if;
      --using given third party regno
      if w_tp_know_reg_no_flag = 1
      then
        w_where := w_where || ' and cla_third_party.' ||
                   bno72.uf_72_third_party_reg_col || '= ''' ||
                   w_param_regnr || '''';
      end if;
      w_query := w_select || w_from || w_where;
      dbs_trace('Eiertel - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_eiertel;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.ownerphone := nvl(substr(regexp_replace(w_eiertel
                                                                                     ,'[^[:digit:]]'
                                                                                     ,null)
                                                                      ,1
                                                                      ,15)
                                                               ,' ');
    dbs_trace('Eiertel: ' ||
              p_hentkarosseri_response.singledamageinfo.ownerphone
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'InsuranceOwner'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'InsuranceOwner'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Forstagnamn - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Forstagnamn := ' || w_user_function_name ||
                        '; end;'
        using out w_forstagnamn;
    else
      w_select := 'select ' || w_tia_table_name || '.' || w_tia_column_name;
      w_from   := ' from cla_case cla_case
                join name name on cla_case.name_id_no = name.id_no ';
      w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
      dbs_trace('Forstagnamn - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_forstagnamn;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.insuranceowner := substr(w_forstagnamn
                                                                      ,1
                                                                      ,25);
    dbs_trace('Forstagnamn: ' ||
              p_hentkarosseri_response.singledamageinfo.insuranceowner
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'InsuranceLicenceNumber'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'InsuranceLicenceNumber'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Forstagregnr - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Forstagregnr := ' || w_user_function_name ||
                        '; end;'
        using out w_forstagregnr;
    else
      w_select := 'select ' || w_tia_table_name || '.' ||
                  bno71.get_obj_column_name_claim_no(w_ws_def_name
                                                    ,'InsuranceLicenceNumber'
                                                    ,w_param_skadenr);
      w_from   := ' from policy_line pl, object object, cla_case cla_case ';
      w_where  := 'where object.suc_seq_no is null';
      w_where  := w_where || ' and pl.suc_seq_no is null';
      w_where  := w_where ||
                  ' and cla_case.policy_line_no = object.agr_line_no';
      w_where  := w_where || ' and pl.agr_line_no = object.agr_line_no';
      w_where  := w_where || ' and cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
      dbs_trace('Forstagregnr - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_forstagregnr;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.insurancelicencenumber := substr(w_forstagregnr
                                                                              ,1
                                                                              ,7);
    dbs_trace('Forstagregnr: ' ||
              p_hentkarosseri_response.singledamageinfo.insurancelicencenumber
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'DamageOperator'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'DamageOperator'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Sbid - executing user function ' || w_user_function_name
               ,c_program);
      execute immediate 'begin :Sbid := ' || w_user_function_name ||
                        '; end;'
        using out w_sbid;
    else
      w_select := 'select ' || w_tia_table_name || '.' || w_tia_column_name;
      w_from   := ' from cla_case cla_case
                join cla_event cla_event on cla_case.cla_event_no = cla_event.cla_event_no ';
      w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
      dbs_trace('Sbid - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_sbid;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.damageoperator := substr(w_sbid
                                                                      ,1
                                                                      ,7);
    dbs_trace('Sbid: ' ||
              p_hentkarosseri_response.singledamageinfo.damageoperator
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'Mileage'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'Mileage'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Kmstand - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Kmstand := ' || w_user_function_name ||
                        '; end;'
        using out w_kmstand;
    else
      w_select := 'select ' || w_tia_table_name || '.' ||
                  bno71.get_obj_column_name_claim_no(w_ws_def_name
                                                    ,'Mileage'
                                                    ,w_param_skadenr);
      w_from   := ' from cla_case cla_case
                join object object on cla_case.policy_line_no = object.agr_line_no ';
      w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
      dbs_trace('Kmstand - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_kmstand;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.mileage := to_number(substr(w_kmstand
                                                                         ,1
                                                                         ,9));
    dbs_trace('Kmstand: ' ||
              p_hentkarosseri_response.singledamageinfo.mileage
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'DamageTypeId'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'DamageTypeId'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Skadetyp - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Skadetyp := ' || w_user_function_name ||
                        '; end;'
        using out w_skadetyp;
    else
      w_select := 'select ' || w_tia_table_name || '.' || w_tia_column_name;
      w_from   := ' from cla_case cla_case
                join cla_event cla_event on cla_case.cla_event_no = cla_event.cla_event_no ';
      w_where  := 'where cla_case.cla_case_no = :w_param_skadenr';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
      dbs_trace('Skadetyp - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_param_skadenr;
      fetch c_cursor
        into w_skadetyp;
      close c_cursor;
    end if;
    p_hentkarosseri_response.singledamageinfo.damagetypeid := nvl(substr(w_skadetyp
                                                                        ,1
                                                                        ,2)
                                                                 ,0);
    dbs_trace('Skadetyp: ' ||
              p_hentkarosseri_response.singledamageinfo.damagetypeid
             ,c_program);
  
    p_hentkarosseri_response.singledamageinfo.claimnumber := substr(w_param_skadenr
                                                                   ,1
                                                                   ,15);
    dbs_trace('Skadenr: ' ||
              p_hentkarosseri_response.singledamageinfo.claimnumber
             ,c_program);
  
    bno72.uf_72_hksd_pre_send_response(p_hentkarosseri_request
                                      ,p_hentkarosseri_response);
  
    ------------------------------------------------------------------------------
    -- Response parameters 'beskytt_xxx'
    ------------------------------------------------------------------------------
    bno72.uf_72_hksd_fill_beskyt_fields(p_hentkarosseri_request
                                       ,p_hentkarosseri_response);
  
    -- if there is more than 1 result we have to fill list with remaining data
    if w_returkod = 2
    then
      goto output_liste;
    end if;
    <<end_main>>
    p_hentkarosseri_response.returncode := w_returkod;
  
    if w_returkod = 3
    then
      p_hentkarosseri_response.returntext := x_reference2('YNO_DBS_ERROR_CODE'
                                                         ,16
                                                         ,'desc');
    end if;
  
    bno74.log_hentkarosseri_response(p_request_seq_no         => w_logging_req_seq_no
                                    ,p_response_status        => log_status_code_success
                                    ,p_err_msg                => null
                                    ,p_hentkarosseri_response => p_hentkarosseri_response);
  
    utl_foundation.close_operation(p_input_token    => v_input_token
                                  ,p_service        => gc_package
                                  ,p_operation      => c_program
                                  ,p_svc_error_code => c_msg_id_other
                                  ,p_result         => p_result);
    p0000.trace_level := 0;
  exception
    when others then
      if c_yno_dbs_ws_definition%isopen
      then
        close c_yno_dbs_ws_definition;
      end if;
      if c_cursor%isopen
      then
        close c_cursor;
      end if;
    
      --technical error (clearing response data, error code 9)
      p_hentkarosseri_response := obj_dbs_hentkarosseri_response();
    
      err_msg := substr(sqlerrm
                       ,1
                       ,1000);
    
      p_hentkarosseri_response.returncode := 9;
      p_hentkarosseri_response.returntext := substr('ERROR_MESSAGE:' ||
                                                    err_msg
                                                   ,1
                                                   ,1000);
    
      begin
        create_error_case('NO31'
                         ,3
                         ,w_param_skadenr
                         ,err_msg);
      exception
        when others then
          err_msg                             := substr(sqlerrm
                                                       ,1
                                                       ,1000);
          p_hentkarosseri_response.returntext := substr(p_hentkarosseri_response.returntext || ' ' ||
                                                        err_msg
                                                       ,1
                                                       ,1000);
      end;
    
      bno74.log_hentkarosseri_response(p_request_seq_no         => w_logging_req_seq_no
                                      ,p_response_status        => log_status_code_error
                                      ,p_err_msg                => err_msg
                                      ,p_hentkarosseri_response => p_hentkarosseri_response);
    
      utl_foundation.handle_service_exception(p_input_token    => v_input_token
                                             ,p_service        => gc_package
                                             ,p_operation      => c_program
                                             ,p_svc_error_code => c_msg_id_other
                                             ,p_result         => p_result);
  end hentkarosseriskadedetaljer;

  ------------------------------------------------------------------------------
  function check_locked_case(p_cla_case_no cla_case.cla_case_no%type)
    return number is
  
    w_locked varchar2(1) := 'N';
  
  begin
    begin
      select 'Y'
        into w_locked
        from cla_case  cc
            ,cla_event ce
       where cc.cla_case_no = p_cla_case_no
         and cc.cla_event_no = ce.cla_event_no
         and ce.locked is not null;
    
    exception
      when no_data_found then
        null;
    end;
  
    if w_locked = 'Y'
    then
      return(0); -- Claim case is locked
    else
      return(1);
    end if;
  
  end check_locked_case;

  ------------------------------------------------------------------------------
  function check_hfg_acceptance_codes(p_operation_request obj_dbs_operation_request
                                     ,p_cla_case_no       cla_case.cla_case_no%type)
    return number is
  
    w_cursor      sys_refcursor;
    w_query       varchar2(1000);
    w_column_name varchar2(3);
    w_accept_code varchar2(3);
  
  begin
    w_column_name := x_site_preference('YNO_DBS_ACCEPT_CODE_COL_NAME');
    w_query       := 'select ' || w_column_name ||
                     ' from cla_case where cla_case_no = :p_case_no';
  
    open w_cursor for w_query
      using p_cla_case_no;
    fetch w_cursor
      into w_accept_code;
    close w_cursor;
  
    if nvl(w_accept_code
          ,'NULL') = bno72.accept_code_pre_approved
       or nvl(w_accept_code
             ,'NULL') = bno72.accept_code_once_accept
    then
      return 1;
    elsif nvl(w_accept_code
             ,'NULL') = bno72.accept_code_uf_accept
    then
      return bno72.uf_72_hfg_apply_accept_rules(p_operation_request
                                               ,p_cla_case_no);
    else
      return 0;
    end if;
  
  end check_hfg_acceptance_codes;
  ------------------------------------------------------------------------------
  function check_sfg_acceptance_codes(p_operation_request obj_dbs_sfg_request
                                     ,p_cla_case_no       cla_case.cla_case_no%type)
    return number is
  
    w_cursor      sys_refcursor;
    w_query       varchar2(1000);
    w_column_name varchar2(3);
    w_accept_code varchar2(3);
  
  begin
    w_column_name := x_site_preference('YNO_DBS_ACCEPT_CODE_COL_NAME');
    w_query       := 'select ' || w_column_name ||
                     ' from cla_case where cla_case_no = :p_case_no';
    open w_cursor for w_query
      using p_cla_case_no;
    fetch w_cursor
      into w_accept_code;
    close w_cursor;
  
    if nvl(w_accept_code
          ,'NULL') = bno72.accept_code_pre_approved
       or nvl(w_accept_code
             ,'NULL') = bno72.accept_code_once_accept
    then
      return 1;
    elsif nvl(w_accept_code
             ,'NULL') = bno72.accept_code_uf_accept
    then
      return bno72.uf_72_sfg_apply_accept_rules(p_operation_request
                                               ,p_cla_case_no);
    else
      return 0;
    end if;
  
  end check_sfg_acceptance_codes;
  ------------------------------------------------------------------------------

  procedure hentfakturagrunnlagstatus(p_input_token        in obj_input_token
                                     ,p_operation_request  in obj_dbs_operation_request
                                     ,p_operation_response out nocopy obj_dbs_operation_response
                                     ,p_result             out nocopy obj_result) is
    c_program          constant varchar2(32) := 'hentFakturagrunnlagStatus';
    c_operation_number constant varchar2(3) := '040';
    c_msg_id_other     constant varchar2(17) := 'DBS-DBS-040-99999';
    err_msg              varchar2(100);
    c_cursor             sys_refcursor;
    w_ws_name            varchar2(100);
    w_ws_method          varchar2(100);
    w_ws_def_name        varchar2(20);
    w_ws_tag_name        varchar2(50);
    w_is_configurable    varchar2(1);
    w_tia_table_name     varchar2(50);
    w_tia_column_name    varchar2(50);
    w_add_condition      varchar2(2000);
    w_user_function      varchar2(1);
    w_user_function_name varchar2(100);
    w_error_message      varchar2(2000);
    w_error_code         number;
    w_cla_case           cla_case%rowtype;
    w_cla_item           cla_item%rowtype;
    w_obj_claim_item     obj_claim_item;
    w_result             obj_result;
    w_company_id_no      varchar2(20);
    w_param_skadenr      varchar2(100);
    w_param_regnr        varchar2(100);
    w_taksttype          integer;
    w_query              varchar2(4000);
    w_select             varchar2(1000);
    w_from               varchar2(1000);
    w_where              varchar2(1000);
    w_regnr_table_column varchar2(500);
    w_egenandel          number(6, 0) := 0;
    w_kontakt_info       varchar2(100);
    w_mailadresse        varchar2(100);
    w_skadenr_fag        varchar2(100);
    w_logging_req_seq_no number;
    v_input_token        obj_input_token;
    w_oppdrags_nr        varchar2(8);
    w_oppdrags_ver_nr    integer;
    v_al_seq_no          agreement_line.agr_line_seq_no%type;
  
    cursor c_yno_dbs_ws_definition(p_ws_flow varchar2) is
      select ws_def_name
        from yno_dbs_ws_definition
       where ws_name = w_ws_name
         and ws_method = w_ws_method
         and flow = p_ws_flow;
  
  begin
    v_input_token         := obj_input_token();
    v_input_token.user_id := x_site_preference('YNO_DBS_CLAIM_USER_ID');
  
    utl_foundation.init_operation(p_input_token => v_input_token
                                 ,p_service     => gc_package
                                 ,p_operation   => c_program);
  
    trace_configuration;
    dbs_trace('START hentFakturagrunnlagStatus'
             ,c_program);
  
    if p_operation_request is null
    then
      dbs_trace('Error: p_operation_request is null'
               ,c_program);
    else
      dbs_trace('OK: p_operation_request is not null'
               ,c_program);
    end if;
  
    bno74.log_hentfaktura_request(p_operation_request
                                 ,w_logging_req_seq_no);
  
    bno73.gw_obj_dbs_operation_request := p_operation_request;
    bno72.gw_obj_dbs_operation_request := p_operation_request;
    w_ws_name                          := 'FakturaGrunnlag';
    w_ws_method                        := 'HentFakturagrunnlag';
  
    open c_yno_dbs_ws_definition('RQ');
    fetch c_yno_dbs_ws_definition
      into w_ws_def_name;
    close c_yno_dbs_ws_definition;
  
    -- Preparing response object
    p_operation_response         := obj_dbs_operation_response();
    p_operation_response.ownrisk := 0;
  
    ---------------------------------------------------------------------------
    -- Process Request with parameters                                       --
    --    ClaimNumber       (cla_case.cla_case_no)
    --    LicenceNumber     (object.xxx)
    --    EstimateNumber
    --    EstimateVersion
    ---------------------------------------------------------------------------
    if p_operation_request.claimnumber is not null
    then
      w_ws_tag_name := 'ClaimNumber';
      bno71.get_mapping_details(w_ws_def_name
                               ,w_ws_tag_name
                               ,w_is_configurable
                               ,w_tia_table_name
                               ,w_tia_column_name
                               ,w_add_condition
                               ,w_user_function
                               ,w_user_function_name);
      if w_user_function = 'Y'
      then
        execute immediate 'begin :v_param_value := ' ||
                          w_user_function_name || '; end;'
          using out w_param_skadenr;
      else
        w_param_skadenr := p_operation_request.claimnumber;
      end if;
    elsif p_operation_request.licencenumber is not null
    then
      w_ws_tag_name := 'LicenceNumber';
      bno71.get_mapping_details(w_ws_def_name
                               ,w_ws_tag_name
                               ,w_is_configurable
                               ,w_tia_table_name
                               ,w_tia_column_name
                               ,w_add_condition
                               ,w_user_function
                               ,w_user_function_name);
      if w_user_function = 'Y'
      then
        execute immediate 'begin :v_param_value := ' ||
                          w_user_function_name || '; end;'
          using out w_param_regnr;
      else
        w_param_regnr := p_operation_request.licencenumber;
      end if;
      w_regnr_table_column := bno71.get_object_where_clause(w_ws_def_name
                                                           ,'LicenceNumber'
                                                           ,w_param_regnr);
    else
      w_error_code := 0;
      goto error_handler;
    end if;
  
    -- Taksttype (GK-glasskade, other - karosseriskade)
    w_taksttype := p_operation_request.recordtype;
    open c_yno_dbs_ws_definition('RS');
    fetch c_yno_dbs_ws_definition
      into w_ws_def_name;
    close c_yno_dbs_ws_definition;
  
    if w_param_skadenr is null
    then
      w_error_code := 6;
      goto error_handler;
    end if;
  
    w_oppdrags_nr     := p_operation_request.estimatenumber;
    w_oppdrags_ver_nr := p_operation_request.estimateversion;
  
    dbs_trace('w_oppdrags_nr: ' || w_oppdrags_nr ||
              ', w_oppdrags_ver_nr: ' || w_oppdrags_ver_nr
             ,c_program);
  
    -- checking if claim exists
    w_query := 'select * from cla_case cla_case where cla_case.cla_case_no = :v_param_skadenr';
    open c_cursor for w_query
      using w_param_skadenr;
    fetch c_cursor
      into w_cla_case;
    close c_cursor;
  
    if w_cla_case.cla_case_no is null
    then
      w_error_code := 7;
      goto error_handler;
    end if;
    dbs_trace('Claim no=' || w_param_skadenr || ' exists.'
             ,c_program);
  
    -- checking if claim item exists
    w_select := 'select *';
    w_from   := ' from cla_item cla_item';
    w_where  := ' where cla_item.cla_case_no = :v_param_skadenr';
    w_where  := w_where || ' and cla_item.newest = :v_param2';
    w_where  := w_where || ' and cla_item.item_type = :v_param3';
    w_where  := w_where || ' and cla_item.subitem_type = :v_param4';
    w_where  := w_where || ' and cla_item.status in(''OP'',''NO'',''RO'')';
  
    bno71.get_mapping_details('Oppdrag'
                             ,'SendOppdrag'
                             ,'RQ'
                             ,'EstimateNumber'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    w_where := w_where || ' and cla_item.' || w_tia_column_name ||
               ' = :v_param5';
    w_query := w_select || w_from || w_where;
  
    open c_cursor for w_query
      using w_param_skadenr, 'Y', 'RE', 'DBS', w_oppdrags_nr;
    fetch c_cursor
      into w_cla_item;
    close c_cursor;
  
    if w_cla_item.cla_case_no is null
    then
      w_error_code := 8;
      goto error_handler;
    end if;
  
    if check_hfg_acceptance_codes(p_operation_request
                                 ,w_cla_case.cla_case_no) = 0
    then
      w_error_code := 9;
      goto error_handler;
    end if;
  
    -- check if excess already exists
    w_select := 'select *';
    w_from   := ' from cla_item cla_item';
    w_where  := ' where cla_item.cla_case_no = :v_param_skadenr';
    w_where  := w_where || ' and cla_item.newest = :v_param2';
    w_where  := w_where || ' and cla_item.item_type = :v_param3';
    w_where  := w_where || ' and cla_item.subitem_type = :v_param4';
    w_where  := w_where || ' and cla_item.status in(''OP'',''NO'',''RO'')';
    w_query  := w_select || w_from || w_where;
  
    -- make subitem_type configurable for deduction and excess
    open c_cursor for w_query
      using w_param_skadenr, 'Y', 'EX', x_site_preference('YNO_DBS_EX_SUBITEM_TYPE');
  
    fetch c_cursor
      into w_cla_item;
    if c_cursor%notfound
    then
      dbs_trace('cursor not found '
               ,c_program);
      if w_taksttype = 2 -- = 'glass claim'
      then
        --adding claim_item of type EXCESS
        select cc.policy_line_seq_no
          into v_al_seq_no
          from cla_case cc
          join agreement_line al
            on al.agr_line_seq_no = cc.policy_line_seq_no
         where cc.cla_case_no = w_param_skadenr;
      
        w_obj_claim_item := bno72.uf_72_hfg_new_claim_item_data(bno72.claim_type_glass
                                                               ,w_cla_case
                                                               ,v_al_seq_no);
        if w_obj_claim_item.risk_no is null
        then
          create_error_case('NO09'
                           ,0
                           ,w_param_skadenr
                           ,bno72.claim_type_glass
                           ,bno72.claim_item_table_name
                           ,v_al_seq_no);
        end if;
        if w_obj_claim_item.subrisk_no is null
        then
          create_error_case('NO10'
                           ,0
                           ,w_param_skadenr
                           ,bno72.claim_type_glass
                           ,bno72.claim_item_table_name
                           ,v_al_seq_no);
        end if;
        w_obj_claim_item.currency_estimate := round_decimals(w_obj_claim_item.currency_estimate);
      
        if w_obj_claim_item.currency_estimate > 0
        then
          select object_id
                ,object_no
                ,object_seq_no
            into w_obj_claim_item.object_id
                ,w_obj_claim_item.object_no
                ,w_obj_claim_item.object_seq_no
            from cla_case
           where cla_case_no = w_param_skadenr;
        
          dbs_trace('Adding claim_item of type EXCESS'
                   ,c_program);
          svc_claim_interactive.addclaimitem(v_input_token
                                            ,w_param_skadenr
                                            ,null
                                            ,w_obj_claim_item
                                            ,w_result);
          if w_result.doeserrorexist
          then
            w_error_code := 4;
            for elem in 1 .. w_result.messages.count
            loop
              w_error_message := w_error_message || w_result.messages(elem)
                                .message_text || ',';
            end loop;
            goto error_handler;
          end if;
          w_egenandel := w_obj_claim_item.currency_estimate;
        end if;
      end if;
    else
      w_egenandel := bno72.uf_72_hfg_get_excess(w_param_skadenr
                                               ,w_cla_item.currency_estimate);
    end if;
    close c_cursor;
    dbs_trace('Excess = ' || w_egenandel
             ,c_program);
  
    -- Response param 'ownrisk'
    p_operation_response.ownrisk := w_egenandel;
  
    ------------------------------------------------------------------------------
    -- Create response object                                                   --
    ------------------------------------------------------------------------------
    -- Response param 'returncode'
    p_operation_response.returncode := 1;
  
    -- Response param 'vatobliged'
    p_operation_response.vatobliged := substr(bno73.uf73_hfg_rs_parm_mva()
                                             ,1
                                             ,1);
  
    -- Response param 'reduction'
    p_operation_response.reduction := bno73.uf73_hfg_rs_parm_avkortbel();
  
    -- Response param 'reductionpercent'
    p_operation_response.reductionpercent := bno73.uf73_hfg_rs_parm_avkortpros();
  
    -- Response param 'ownriskdeduction'
    p_operation_response.ownriskdeduction := bno73.uf73_hfg_rs_parm_egenandel_fo();
  
    if w_taksttype = 2 -- = 'glass claim'
    then
      -- Response param 'companydatatext'
      p_operation_response.companydatatext := substr(bno73.uf73_hfg_rs_parm_tekst1()
                                                    ,1
                                                    ,1000);
    
    end if;
    ------------------------------------------------------------------------------
    -- Response param 'ContactInfo'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'ContactInfo'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    w_company_id_no := x_site_preference('YNO_DBS_COMPANY_ID_NO');
  
    if w_user_function = 'Y'
    then
      dbs_trace('Kontakt_info - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Kontakt_info := ' || w_user_function_name ||
                        '; end;'
        using out w_kontakt_info;
    else
      w_select := 'select ' || w_tia_column_name;
      w_from   := ' from ' || w_tia_table_name;
      w_where  := ' where id_no = :w_company_id_no';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
    
      dbs_trace('Kontakt_info - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_company_id_no;
      fetch c_cursor
        into w_kontakt_info;
      close c_cursor;
    end if;
    p_operation_response.contactinfo := substr(w_kontakt_info
                                              ,1
                                              ,70);
  
    dbs_trace('Kontakt_info: ' || p_operation_response.contactinfo
             ,c_program);
    ------------------------------------------------------------------------------
    -- Response param 'EmailAddress'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'EmailAddress'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Mailadresse - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Mailadresse := ' || w_user_function_name ||
                        '; end;'
        using out w_mailadresse;
    else
      w_select := 'select ' || w_tia_column_name;
      w_from   := ' from ' || w_tia_table_name;
      w_where  := ' where name_id_no = :w_company_id_no';
    
      if w_add_condition is not null
      then
        w_where := w_where || ' and ' || w_add_condition;
      end if;
      w_query := w_select || w_from || w_where;
    
      dbs_trace('Mailadresse - executing query: ' || w_query
               ,c_program);
      open c_cursor for w_query
        using w_company_id_no;
      fetch c_cursor
        into w_mailadresse;
      close c_cursor;
    
    end if;
    p_operation_response.emailaddress := substr(w_mailadresse
                                               ,1
                                               ,70);
    dbs_trace('Mailadresse: ' || p_operation_response.emailaddress
             ,c_program);
  
    ------------------------------------------------------------------------------
    -- Response param 'ClaimNumber'
    ------------------------------------------------------------------------------
    bno71.get_mapping_details(w_ws_def_name
                             ,'ClaimNumber'
                             ,w_is_configurable
                             ,w_tia_table_name
                             ,w_tia_column_name
                             ,w_add_condition
                             ,w_user_function
                             ,w_user_function_name);
  
    if w_user_function = 'Y'
    then
      dbs_trace('Skadenr_fag - executing user function ' ||
                w_user_function_name
               ,c_program);
      execute immediate 'begin :Skadenr_fag := ' || w_user_function_name ||
                        '; end;'
        using out w_skadenr_fag;
    else
      if upper(w_tia_table_name) = 'CLA_CASE'
         and upper(w_tia_column_name) = 'CLA_CASE_NO'
      then
        w_skadenr_fag := w_param_skadenr;
      else
        w_select := 'select ' || w_tia_column_name;
        w_from   := ' from ' || w_tia_table_name;
        w_where  := ' where cla_case.cla_case_no = :v_param_skadenr';
        if w_add_condition is not null
        then
          w_where := w_where || ' and ' || w_add_condition;
        end if;
        w_query := w_select || w_from || w_where;
      
        dbs_trace('Skadenr_fag - executing query: ' || w_query
                 ,c_program);
        open c_cursor for w_query
          using w_param_skadenr;
        fetch c_cursor
          into w_skadenr_fag;
        close c_cursor;
      end if;
    end if;
    p_operation_response.claimnumber := substr(w_skadenr_fag
                                              ,1
                                              ,15);
    dbs_trace('Skadenr_fag: ' || p_operation_response.claimnumber
             ,c_program);
  
    bno72.uf_72_hfg_pre_send_response(p_operation_request
                                     ,p_operation_response);
  
    goto end_main;
  
    <<error_handler>>
    p_operation_response.returncode := 8;
    if w_error_code is not null
    then
      if w_error_message is null
      then
        w_error_message := x_reference2('YNO_DBS_ERROR_CODE'
                                       ,w_error_code
                                       ,'desc');
      else
        w_error_message := x_reference2('YNO_DBS_ERROR_CODE'
                                       ,w_error_code
                                       ,'desc') || ':' || w_error_message;
      end if;
    end if;
    create_error_case('NO24'
                     ,2
                     ,w_param_skadenr
                     ,w_error_message);
    p_operation_response.returntext := substr(w_error_message
                                             ,1
                                             ,1000);
    <<end_main>>
    null;
    bno74.log_hentfaktura_response(p_request_seq_no     => w_logging_req_seq_no
                                  ,p_response_status    => log_status_code_success
                                  ,p_err_msg            => null
                                  ,p_operation_response => p_operation_response);
  
    utl_foundation.close_operation(p_input_token    => v_input_token
                                  ,p_service        => gc_package
                                  ,p_operation      => c_program
                                  ,p_svc_error_code => c_msg_id_other
                                  ,p_result         => p_result);
    p0000.trace_level := 0;
  exception
    when others then
      if c_yno_dbs_ws_definition%isopen
      then
        close c_yno_dbs_ws_definition;
      end if;
      if c_cursor%isopen
      then
        close c_cursor;
      end if;
      p_operation_response         := obj_dbs_operation_response();
      p_operation_response.ownrisk := 0;
    
      err_msg := substr(sqlerrm
                       ,1
                       ,1000);
    
      p_operation_response.returntext := substr('ERROR_MESSAGE:' || err_msg
                                               ,1
                                               ,1000);
    
      begin
        create_error_case('NO34'
                         ,3
                         ,w_param_skadenr
                         ,err_msg);
      exception
        when others then
          err_msg                         := substr(sqlerrm
                                                   ,1
                                                   ,1000);
          p_operation_response.returntext := substr(p_operation_response.returntext || ' ' ||
                                                    err_msg
                                                   ,1
                                                   ,1000);
      end;
    
      p_operation_response.returncode := 8;
    
      bno74.log_hentfaktura_response(p_request_seq_no     => w_logging_req_seq_no
                                    ,p_response_status    => log_status_code_error
                                    ,p_err_msg            => err_msg
                                    ,p_operation_response => p_operation_response);
    
      utl_foundation.handle_service_exception(p_input_token    => v_input_token
                                             ,p_service        => gc_package
                                             ,p_operation      => c_program
                                             ,p_svc_error_code => c_msg_id_other
                                             ,p_result         => p_result);
    
  end hentfakturagrunnlagstatus;
  ------------------------------------------------------------------------------

  procedure sendfakturagrunnlag(p_input_token        in obj_input_token
                               ,p_operation_request  in obj_dbs_sfg_request
                               ,p_operation_response out nocopy obj_dbs_sfg_response
                               ,p_result             out nocopy obj_result) is
    c_program          constant varchar2(32) := 'sendFakturagrunnlag';
    c_operation_number constant varchar2(3) := '050';
    c_msg_id_other     constant varchar2(17) := 'DBS-DBS-050-99999';
    err_msg               varchar2(100);
    c_cursor              sys_refcursor;
    w_ws_name             varchar2(100);
    w_ws_method           varchar2(100);
    w_ws_def_name         varchar2(20);
    w_ws_tag_name         varchar2(50);
    w_is_configurable     varchar2(1);
    w_tia_table_name      varchar2(50);
    w_tia_column_name     varchar2(50);
    w_add_condition       varchar2(2000);
    w_user_function       varchar2(1);
    w_user_function_name  varchar2(100);
    w_cla_case            cla_case%rowtype;
    w_cla_item            cla_item%rowtype;
    w_error_message       varchar2(2000);
    w_error_code          number;
    w_param_skadenr       varchar2(100);
    w_param_regnr         varchar2(100);
    w_param_skadedato     date;
    w_faktura_amt         number;
    w_total_amount        number;
    w_diff                number;
    w_re_amt              number;
    w_kontonr             varchar2(11);
    w_means_pay_no        number;
    w_query               varchar2(4000);
    w_select              varchar2(1000);
    w_from                varchar2(1000);
    w_where               varchar2(1000);
    w_regnr_table_column  varchar2(500);
    w_item_type_list      item_type;
    w_currency_amt_list   currency_amt_type;
    w_seq_no_list         seq_no_type;
    w_currency_code_list  currency_code_type;
    w_rec_id_no_list      receiver_id_no_type;
    w_claim_acc_item      obj_claim_acc_item;
    w_input_token         obj_input_token;
    w_result              obj_result;
    w_logging_req_seq_no  number;
    v_input_token         obj_input_token;
    w_taksttype           integer;
    w_cla_paym_item_where varchar2(100);
    w_count               number;
    w_messages            tab_message;
    w_closed_claim_cnt    number := 0;
  
    cursor c_yno_dbs_ws_definition(p_ws_flow varchar2) is
      select ws_def_name
        from yno_dbs_ws_definition
       where ws_name = w_ws_name
         and ws_method = w_ws_method
         and flow = p_ws_flow;
  
    cursor c_means_pay_no(p_name_id_no     number
                         ,p_payment_method varchar2
                         ,p_bank_acc_no    varchar2) is
      select means_pay_no
        from acc_payment_details
       where name_id_no = p_name_id_no
         and payment_method = p_payment_method
         and bank_account_no = p_bank_acc_no;
  
    -- make subitem_type configurable for deduction and excess
    cursor c_claim_items(p_cla_case_no number) is
      select cla_item_no
            ,currency_estimate
            ,item_type
        from cla_item
       where newest = 'Y'
         and ((item_type = 'EX' and
             subitem_type = x_site_preference('YNO_DBS_EX_SUBITEM_TYPE')) or
             (item_type = 'EX' and
             subitem_type = x_site_preference('YNO_DBS_DE_SUBITEM_TYPE')) or
             (item_type = 'RE' and subitem_type = 'DBS'))
         and status in ('OP'
                       ,'NO'
                       ,'RO')
         and cla_case_no = p_cla_case_no;
  
  begin
    -- Initialize everything
    v_input_token         := obj_input_token();
    v_input_token.user_id := x_site_preference('YNO_DBS_CLAIM_USER_ID');
  
    utl_foundation.init_operation(p_input_token => v_input_token
                                 ,p_service     => gc_package
                                 ,p_operation   => c_program);
  
    trace_configuration;
    dbs_trace('START sendFakturagrunnlag'
             ,c_program);
  
    bno74.log_sendfaktura_request(p_operation_request
                                 ,w_logging_req_seq_no);
  
    bno73.gw_obj_dbs_sfg_request := p_operation_request;
    bno72.gw_obj_dbs_sfg_request := p_operation_request;
    w_ws_name                    := 'FakturaGrunnlag';
    w_ws_method                  := 'SendFakturagrunnlag';
  
    open c_yno_dbs_ws_definition('RQ');
    fetch c_yno_dbs_ws_definition
      into w_ws_def_name;
    close c_yno_dbs_ws_definition;
  
    -- Preparing response object and copying reqest data into response data
    p_operation_response := obj_dbs_sfg_response();
  
    ---------------------------------------------------------------------------
    -- Process Request with parameters                                       --
    --    ClaimNumber             (cla_event.cla_case_no)
    --    Licencenumber           (object.xxx)
    --    DamageDate              (cla_event.incident_date)
    --    BankAccountNumber
    --    InvoiceTotalAmount
    --    CustomerReferenceNumber (ACC_ITEM.ITEM_REFERENCE)
    --    Orgnr_verksted          Workshop organization number
    --    WorkshopNumber          Workshop number
    --    WorkshopName            Workshop name
    ---------------------------------------------------------------------------
    if p_operation_request.claimnumber is not null
    then
      w_ws_tag_name := 'ClaimNumber';
      bno71.get_mapping_details(w_ws_def_name
                               ,w_ws_tag_name
                               ,w_is_configurable
                               ,w_tia_table_name
                               ,w_tia_column_name
                               ,w_add_condition
                               ,w_user_function
                               ,w_user_function_name);
      if w_user_function = 'Y'
      then
        execute immediate 'begin :v_param_value := ' ||
                          w_user_function_name || '; end;'
          using out w_param_skadenr;
      else
        w_param_skadenr := p_operation_request.claimnumber;
      end if;
    elsif p_operation_request.licencenumber is not null
    then
      w_ws_tag_name := 'LicenceNumber';
      bno71.get_mapping_details(w_ws_def_name
                               ,w_ws_tag_name
                               ,w_is_configurable
                               ,w_tia_table_name
                               ,w_tia_column_name
                               ,w_add_condition
                               ,w_user_function
                               ,w_user_function_name);
      if w_user_function = 'Y'
      then
        execute immediate 'begin :v_param_value := ' ||
                          w_user_function_name || '; end;'
          using out w_param_regnr;
      else
        w_param_regnr := p_operation_request.licencenumber;
      end if;
      w_regnr_table_column := bno71.get_object_where_clause(w_ws_def_name
                                                           ,'LicenceNumber'
                                                           ,w_param_regnr);
      if p_operation_request.damagedate is not null
      then
        w_ws_tag_name := 'DamageDate';
        bno71.get_mapping_details(w_ws_def_name
                                 ,w_ws_tag_name
                                 ,w_is_configurable
                                 ,w_tia_table_name
                                 ,w_tia_column_name
                                 ,w_add_condition
                                 ,w_user_function
                                 ,w_user_function_name);
        if w_user_function = 'Y'
        then
          execute immediate 'begin :v_param_value := ' ||
                            w_user_function_name || '; end;'
            using out w_param_skadedato;
        else
          w_param_skadedato := p_operation_request.damagedate;
        end if;
      end if;
    else
      w_error_code := 0;
      goto error_handler;
    end if;
    if w_param_skadenr is null
    then
      w_error_code := 6;
      goto error_handler;
    end if;
  
    w_kontonr     := p_operation_request.bankaccountnumber;
    w_faktura_amt := round_decimals(bno72.uf_72_sfg_invoice_amt(p_operation_request
                                                               ,w_param_skadenr));
    w_taksttype   := p_operation_request.recordtype;
    dbs_trace('Kontonr: ' || w_kontonr || ', invoice_amt: ' ||
              w_faktura_amt || ', recordtype: ' || w_taksttype
             ,c_program);
  
    ---------------------------------------------------------------------------
    -- Create response object                                                --
    ---------------------------------------------------------------------------
  
    -- checking if claim exists
    w_query := 'select * from cla_case cla_case where cla_case.cla_case_no = :v_param_skadenr';
    open c_cursor for w_query
      using w_param_skadenr;
    fetch c_cursor
      into w_cla_case;
    close c_cursor;
  
    if w_cla_case.cla_case_no is null
    then
      w_error_code := 7;
      goto error_handler;
    end if;
  
    -- checking if claim item exists
    w_select := 'select *';
    w_from   := ' from cla_item cla_item';
    w_where  := ' where cla_item.cla_case_no = :v_param_skadenr';
    w_where  := w_where || ' and cla_item.newest = :v_param2';
    w_where  := w_where || ' and cla_item.item_type = :v_param3';
    w_where  := w_where || ' and cla_item.subitem_type = :v_param4';
    w_where  := w_where || ' and cla_item.status in(''OP'',''NO'',''RO'')';
    w_query  := w_select || w_from || w_where;
  
    open c_cursor for w_query
      using w_param_skadenr, 'Y', 'RE', 'DBS';
    fetch c_cursor
      into w_cla_item;
    close c_cursor;
  
    if w_cla_item.cla_case_no is null
    then
      w_error_code := 8;
      goto error_handler;
    end if;
    dbs_trace('Claim ' || w_cla_item.cla_case_no || ' exists.'
             ,c_program);
  
    --checking if claim is 'Accepted for DBS'
    if check_sfg_acceptance_codes(p_operation_request
                                 ,w_cla_case.cla_case_no) = 0
    then
      w_error_code := 9;
      goto error_handler;
    end if;
    dbs_trace('Claim ' || w_cla_item.cla_case_no || ' accepted for DBS.'
             ,c_program);
  
    -- Check for locked claim case
    if check_locked_case(w_cla_case.cla_case_no) = 0
    then
      w_error_code := 15;
      goto error_handler;
    end if;
    dbs_trace('Claim ' || w_cla_item.cla_case_no || ' is not locked.'
             ,c_program);
  
    -- check if invoice amount <= RE-EX
    w_total_amount := 0;
  
    -- make subitem_type configurable for deduction and excess
    w_select := 'select cla_item.item_type, cla_item.currency_estimate,
                       cla_item.currency_code, cla_item.seq_no, cla_item.receiver_id_no';
    w_from   := ' from cla_item cla_item';
    w_where  := ' where cla_item.cla_case_no = ' || w_param_skadenr;
    w_where  := w_where || ' and cla_item.newest = ''Y''';
    w_where  := w_where ||
                ' and ((cla_item.item_type = ''RE'' and cla_item.subitem_type = ''DBS'') or (cla_item.item_type = ''EX'' and cla_item.subitem_type = x_site_preference(''YNO_DBS_EX_SUBITEM_TYPE'')) or (cla_item.item_type = ''EX'' and cla_item.subitem_type = x_site_preference(''YNO_DBS_DE_SUBITEM_TYPE'')))';
    w_where  := w_where || ' and cla_item.status in(''OP'',''NO'',''RO'')';
    w_where  := w_where || ' and cla_item.currency_estimate > 0';
    w_query  := w_select || w_from || w_where;
  
    dbs_trace('w_query: ' || w_query
             ,c_program);
  
    execute immediate w_query bulk collect
      into w_item_type_list, w_currency_amt_list, w_currency_code_list, w_seq_no_list, w_rec_id_no_list;
  
    w_claim_acc_item                     := obj_claim_acc_item();
    w_claim_acc_item.claim_payment_items := tab_claim_payment_item();
  
    --checking total amount
    for elem in 1 .. w_item_type_list.count
    loop
      if w_item_type_list(elem) = 'RE'
      then
        w_total_amount := w_total_amount + w_currency_amt_list(elem);
      elsif w_item_type_list(elem) = 'EX'
      then
        w_total_amount := w_total_amount - w_currency_amt_list(elem);
      end if;
    end loop;
    w_diff := w_total_amount - w_faktura_amt;
    dbs_trace('w_total_amount: ' || w_total_amount || '  ' ||
              'w_faktura_amt: ' || w_faktura_amt
             ,c_program);
  
    for elem in 1 .. w_item_type_list.count
    loop
      --preparing data for automatic payment
      if w_item_type_list(elem) = 'RE'
         or w_item_type_list(elem) = 'EX'
      then
        w_claim_acc_item.claim_payment_items.extend;
        w_claim_acc_item.claim_payment_items(elem) := obj_claim_payment_item();
        w_claim_acc_item.claim_payment_items(elem).cla_item_seq_no := w_seq_no_list(elem);
        w_claim_acc_item.claim_payment_items(elem).currency_amount := w_currency_amt_list(elem);
        w_claim_acc_item.claim_payment_items(elem).currency_code := w_currency_code_list(elem);
        w_claim_acc_item.claim_payment_items(elem).payment_type := bno72.uf_72_sfg_get_payment_type(w_param_skadenr
                                                                                                   ,w_seq_no_list(elem));
      end if;
    
      if w_item_type_list(elem) = 'RE'
      then
        w_claim_acc_item.receiver_id_no := w_rec_id_no_list(elem);
        w_claim_acc_item.currency_code  := w_currency_code_list(elem);
        if w_diff > 0
        then
          w_re_amt := w_currency_amt_list(elem);
          if w_re_amt > w_diff
          then
            w_claim_acc_item.claim_payment_items(elem).currency_amount := w_re_amt -
                                                                          w_diff;
            w_diff := 0;
          else
            w_claim_acc_item.claim_payment_items(elem).currency_amount := 0;
            w_diff := w_diff - w_re_amt;
          end if;
        end if;
      end if;
    end loop;
  
    if round_decimals(w_faktura_amt) > round_decimals(w_total_amount)
    then
      if bno72.uf_72_sfg_pre_create_case(w_param_skadenr
                                        ,w_total_amount
                                        ,w_faktura_amt) = 0
      then
        create_error_case('NO07'
                         ,0
                         ,w_param_skadenr
                         ,w_faktura_amt
                         ,w_total_amount);
      end if;
      w_error_code := '12';
      goto error_handler;
    else
      --automatic payout claim RE-EX
      w_input_token                   := obj_input_token();
      w_input_token.user_id           := x_site_preference('YNO_DBS_CLAIM_USER_ID');
      w_claim_acc_item.claim_no       := w_param_skadenr;
      w_claim_acc_item.payment_method := x_site_preference('YNO_DBS_PAYMENT_METHOD');
    
      -- acc_payment_details for payment
      open c_means_pay_no(w_claim_acc_item.receiver_id_no
                         ,w_claim_acc_item.payment_method
                         ,w_kontonr);
      fetch c_means_pay_no
        into w_means_pay_no;
      if c_means_pay_no%notfound
      then
        t6064.clr;
        bno72.uf_72_sfg_create_paym_details(p_operation_request
                                           ,w_claim_acc_item
                                           ,t6064.rec);
        t6064.ins;
        w_means_pay_no := t6064.rec.means_pay_no;
      end if;
      close c_means_pay_no;
    
      w_claim_acc_item.means_pay_no := w_means_pay_no;
      dbs_trace('Start creating claim payment.'
               ,c_program);
      svc_claim_payment.createclaimpayment(w_input_token
                                          ,w_claim_acc_item
                                          ,w_result);
      dbs_trace('Claim payment created.'
               ,c_program);
    
      --add extra information to created acc_item
      bno72.uf_72_sfg_post_create_acc_item(w_claim_acc_item.acc_item_no);
    
      --getting item_id updating kid_nr in acc_item
      w_count := 1;
      for el in 1 .. w_claim_acc_item.claim_payment_items.count
      loop
        if w_count = 1
        then
          w_cla_paym_item_where := '(';
        end if;
        if w_count = w_claim_acc_item.claim_payment_items.count
        then
          w_cla_paym_item_where := w_cla_paym_item_where || w_claim_acc_item.claim_payment_items(el)
                                  .cla_payment_item_no || ')';
        else
          w_cla_paym_item_where := w_cla_paym_item_where || w_claim_acc_item.claim_payment_items(el)
                                  .cla_payment_item_no || ',';
        end if;
        w_count := w_count + 1;
      end loop;
    
      if w_result.doeserrorexist
      then
        for elem in 1 .. w_result.messages.count
        loop
          w_error_message := w_error_message || w_result.messages(elem)
                            .message_text || ',';
        end loop;
        w_error_code := '11';
        goto error_handler;
      end if;
    
      --closing all claim items
      if w_taksttype = 1 -- = 'general claims'
      then
        for rec in c_claim_items(w_param_skadenr)
        loop
          if rec.currency_estimate = 0
          then
            dbs_trace('Start closing claim item  ' || rec.cla_item_no
                     ,c_program);
            p5600.close_claim_item(rec.cla_item_no
                                  ,'CL');
            w_closed_claim_cnt := w_closed_claim_cnt + 1;
            w_messages         := p0000.get_and_clear_messages;
            for elem in 1 .. w_messages.count
            loop
              if w_messages(elem).message_type = p0000.msg_type_error
              then
                w_error_message := w_error_message || w_messages(elem)
                                  .message_text || ',';
                w_error_code    := '11';
                goto error_handler;
              end if;
            end loop;
          elsif rec.item_type = 'RE'
          then
            create_error_case('NO08'
                             ,0
                             ,w_param_skadenr
                             ,rec.currency_estimate);
          end if;
        end loop;
        if w_closed_claim_cnt > 0
        then
          create_error_case('NO11'
                           ,0
                           ,w_param_skadenr);
        end if;
        dbs_trace('Closed ' || w_closed_claim_cnt || ' claim items.'
                 ,c_program);
      end if;
    
      --close claim
      if w_taksttype = 2 -- = 'glass claim'
      then
        dbs_trace('Start closing claim ' || w_param_skadenr
                 ,c_program);
        svc_claim_interactive.modifystatusclosemainclaim(w_input_token
                                                        ,w_param_skadenr
                                                        ,'CL'
                                                        ,'Y'
                                                        ,null
                                                        ,null
                                                        ,w_result);
        if w_result.doeserrorexist
        then
          for elem in 1 .. w_result.messages.count
          loop
            w_error_message := w_error_message || w_result.messages(elem)
                              .message_text || ',';
          end loop;
          w_error_code := '11';
          goto error_handler;
        end if;
        dbs_trace('Claim ' || w_param_skadenr || ' closed.'
                 ,c_program);
      end if;
    
      --insert KID
      if p_operation_request.customerreferencenumber is not null
      then
        w_ws_tag_name := 'CustomerReferenceNumber';
        bno71.get_mapping_details(w_ws_def_name
                                 ,w_ws_tag_name
                                 ,w_is_configurable
                                 ,w_tia_table_name
                                 ,w_tia_column_name
                                 ,w_add_condition
                                 ,w_user_function
                                 ,w_user_function_name);
        w_select := 'update acc_item set ' || w_tia_column_name ||
                    '= :kid_nr where means_pay_no = :means_pay_no ';
        w_select := w_select ||
                    'and item_id in (select item_id from cla_payment_item where cla_payment_item_no in ' ||
                    w_cla_paym_item_where || ')';
        execute immediate w_select
          using in p_operation_request.customerreferencenumber, w_means_pay_no;
      elsif p_operation_request.invoicenumber is not null
      then
        w_ws_tag_name := 'InvoiceNumber';
        bno71.get_mapping_details(w_ws_def_name
                                 ,w_ws_tag_name
                                 ,w_is_configurable
                                 ,w_tia_table_name
                                 ,w_tia_column_name
                                 ,w_add_condition
                                 ,w_user_function
                                 ,w_user_function_name);
        w_select := 'update acc_item set ' || w_tia_column_name ||
                    '= :fakturanr where means_pay_no = :means_pay_no ';
        w_select := w_select ||
                    'and item_id in (select item_id from cla_payment_item where cla_payment_item_no in ' ||
                    w_cla_paym_item_where || ')';
        execute immediate w_select
          using in p_operation_request.invoicenumber, w_means_pay_no;
      end if;
    
    end if;
  
    ---------------------------------------------------------------------------
    -- Create response object (the same as request)                          --
    ---------------------------------------------------------------------------
    p_operation_response.returncode := 1;
  
    bno72.uf_72_sfg_pre_send_response(p_operation_request
                                     ,p_operation_response);
  
    goto end_main;
  
    <<error_handler>>
    p_operation_response.returncode := 8;
    if w_error_code is not null
    then
      if w_error_message is null
      then
        w_error_message := x_reference2('YNO_DBS_ERROR_CODE'
                                       ,w_error_code
                                       ,'desc');
      else
        w_error_message := x_reference2('YNO_DBS_ERROR_CODE'
                                       ,w_error_code
                                       ,'desc') || ':' || w_error_message;
      end if;
    end if;
    create_error_case('NO25'
                     ,2
                     ,w_param_skadenr
                     ,w_error_message);
    p_operation_response.returntext := substr(w_error_message
                                             ,1
                                             ,1000);
  
    <<end_main>>
    null;
    bno74.log_sendfaktura_response(p_request_seq_no     => w_logging_req_seq_no
                                  ,p_response_status    => log_status_code_success
                                  ,p_err_msg            => err_msg
                                  ,p_operation_response => p_operation_response);
  
    p0000.trace_level := 0;
    utl_foundation.close_operation(p_input_token    => v_input_token
                                  ,p_service        => gc_package
                                  ,p_operation      => c_program
                                  ,p_svc_error_code => c_msg_id_other
                                  ,p_result         => p_result);
  exception
    when others then
      if c_yno_dbs_ws_definition%isopen
      then
        close c_yno_dbs_ws_definition;
      end if;
      if c_cursor%isopen
      then
        close c_cursor;
      end if;
    
      p_operation_response := obj_dbs_sfg_response();
    
      dbs_trace(substr('SFG ERROR MESSAGE: ' || sqlerrm || chr(10) ||
                       'Call stack = ' || dbms_utility.format_call_stack
                      ,1
                      ,2000)
               ,c_program);
    
      err_msg                         := substr(sqlerrm
                                               ,1
                                               ,1000);
      p_operation_response.returntext := substr('ERROR_MESSAGE:' || err_msg
                                               ,1
                                               ,1000);
    
      begin
        create_error_case('NO35'
                         ,3
                         ,w_param_skadenr
                         ,err_msg);
      exception
        when others then
          err_msg                         := substr(sqlerrm
                                                   ,1
                                                   ,1000);
          p_operation_response.returntext := substr(p_operation_response.returntext || ' ' ||
                                                    err_msg
                                                   ,1
                                                   ,1000);
      end;
      p_operation_response.returncode := 8;
    
      bno74.log_sendfaktura_response(p_request_seq_no     => w_logging_req_seq_no
                                    ,p_response_status    => log_status_code_error
                                    ,p_err_msg            => err_msg
                                    ,p_operation_response => p_operation_response);
    
      utl_foundation.handle_service_exception(p_input_token    => v_input_token
                                             ,p_service        => gc_package
                                             ,p_operation      => c_program
                                             ,p_svc_error_code => c_msg_id_other
                                             ,p_result         => p_result);
    
  end sendfakturagrunnlag;

end svc_dbs;
/
