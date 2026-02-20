SELECT 
    nome_motorista,
    data_referencia,
    score_conducao,
    tempo_ocioso_minutos,
    qtd_infracoes_velocidade
FROM fleetops_project.gold.agg_driver_performance_daily
WHERE score_conducao < 50
  AND data_referencia = CURRENT_DATE;