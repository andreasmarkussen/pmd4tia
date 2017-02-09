create or replace package positive_package is
  -- Comment
end positive_package;
/
create or replace package body positive_package is
  procedure test(p_parameter number) is
    w_program  p0000.program%type := p0000.program;
  begin
    z_program('B1234.test');
    z_trace('Start');
    z_trace('parameter is :' || p_parameter);

    z_trace('End');
    z_program(w_program);
  exception
    when others then
      z_error_handle; --or "z_error;" in old code since it will just call z_error_handle
  end test;
end positive_package;
/
