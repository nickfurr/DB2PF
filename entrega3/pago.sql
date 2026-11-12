create or replace procedure pago (
    p_monto   in  number,
    p_reserva in  reserva.id_reserva%type,
    p_metodo  in  pago.metodo%type,
    p_idpago  out pago.id_pago%type,
    p_fecha   in  pago.fecha%type default sysdate
) is
    var_estado     reserva.estado%type;
    var_pagado     pago.monto%type;
    var_total_hab  number;
    var_total_serv number;
    var_apagar     number;
    var_fecha      date := nvl(p_fecha, sysdate);

    e_check_violado exception;
    pragma exception_init(e_check_violado, -2290);
begin
    savepoint sp_pago_inicio;

    if p_monto is null or p_monto <= 0 then
        raise_application_error(-20001, 'El monto del pago debe ser mayor que cero.');
    end if;

    if p_metodo is null then
        raise_application_error(-20002, 'Se debe establecer un metodo de pago.');
    end if;

    if var_fecha > sysdate then
        raise_application_error(-20003, 'La fecha del pago no puede ser futura.');
    end if;

    -- Verificar que la reserva exista y no este cancelada (bloqueo para evitar doble pago concurrente)
    select estado
      into var_estado
      from reserva
     where id_reserva = p_reserva
       for update;

    if var_estado = 'cancelada' then
        raise_application_error(-20006, 'No se puede registrar un pago sobre una reserva cancelada.');
    end if;

    -- Todo lo que llevamos pagado con exito
    select nvl(sum(monto), 0)
      into var_pagado
      from pago
     where id_reserva = p_reserva
       and estado = 'exitoso';

    -- Deuda original: hospedaje + servicios
    select nvl(sum((checkout - checkin) * precio_noche_calculado), 0)
      into var_total_hab
      from reserva_habitacion
     where id_reserva = p_reserva;

    select nvl(sum(cantidad * precio_cobrado), 0)
      into var_total_serv
      from reserva_servicio
     where id_reserva = p_reserva;

    var_apagar := var_total_hab + var_total_serv;

    if var_apagar < var_pagado + p_monto then
        raise_application_error(-20004, 'El pago excede la deuda de la reserva.');
    end if;

    insert into pago (id_reserva, fecha, monto, metodo, estado)
    values (p_reserva, var_fecha, p_monto, p_metodo, 'exitoso')
    returning id_pago into p_idpago;

exception
    when no_data_found then
        rollback to sp_pago_inicio;
        raise_application_error(-20005, 'La reserva ' || nvl(to_char(p_reserva), '(nula)') || ' no existe.');
    when e_check_violado then
        rollback to sp_pago_inicio;
        raise_application_error(-20007, 'Metodo de pago invalido. Valores permitidos: tarjeta de credito, tarjeta debito, PSE, transferencia, efectivo.');
    when others then
        rollback to sp_pago_inicio;
        raise;
end pago;
/

