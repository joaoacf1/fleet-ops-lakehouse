SELECT 
    truck_id, 
    COUNT(event_id) as qtd_eventos_orfaos,
    MAX(data_hora) as ultimo_evento
FROM fleetops_project.gold.fact_telemetria
WHERE motorista_fk = -1 
  AND DATE(data_hora) = CURRENT_DATE
GROUP BY truck_id;