# 🚛 FleetOps Lakehouse: Modern Data Platform

![Databricks](https://img.shields.io/badge/Databricks-FF3621?style=for-the-badge&logo=Databricks&logoColor=white)
![Delta Lake](https://img.shields.io/badge/Delta_Lake-00A4E4?style=for-the-badge&logo=databricks&logoColor=white)
![Apache Spark](https://img.shields.io/badge/Apache_Spark-E25A1C?style=for-the-badge&logo=apache-spark&logoColor=white)
![AWS S3](https://img.shields.io/badge/AWS_S3-569A31?style=for-the-badge&logo=amazons3&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)

Um pipeline de engenharia de dados *end-to-end* construído no Databricks utilizando a Medallion Architecture. 

O projeto processa dados de telemetria IoT de uma frota de caminhões em conjunto com dados transacionais de um ERP, resolvendo o problema de rastreabilidade temporal de motoristas para cálculo de métricas de performance e consumo de combustível.

<img width="2660" height="1209" alt="Image" src="https://github.com/user-attachments/assets/dfc0d586-4223-4568-80e9-f429e02457c2" />

## 📌 Arquitetura e Fluxo de Dados

<img width="1112" height="510" alt="Image" src="https://github.com/user-attachments/assets/af546787-adae-47dd-b02a-075825b8ff55" />

A infraestrutura foi desenhada para lidar com a assincronicidade entre eventos de sensores em tempo real e as escalas de trabalho legadas do sistema de RH.

### Fontes de Dados
* **IoT Telemetry (AWS S3):** Simulação de sensores enviando arquivos JSON com dados de GPS, RPM, velocidade, temperatura e nível de combustível.
* **ERP Relacional (PostgreSQL/Supabase):** Banco de dados transacional mantendo o cadastro de Caminhões, Motoristas e os históricos de alocação (turnos).

### Pipeline Medallion (Delta Lake)

1. **Bronze Layer (Raw Data):** * Ingestão incremental dos arquivos JSON do S3 utilizando **Databricks Auto Loader** (`cloudFiles`), com inferência e evolução automática de schema.
   * Integração com o PostgreSQL configurada nativamente via UI do Databricks (Lakehouse Federation / External Connections), permitindo a leitura direta do banco transacional.
   * Criação dinâmica de catálogos e schemas (`CREATE SCHEMA IF NOT EXISTS`), dispensando a necessidade de scripts isolados de setup de infraestrutura.

2. **Silver Layer (Cleansing & Conformed):**
   * Deduplicação de eventos IoT em atraso ou reprocessados utilizando `MERGE INTO` e particionamento (`ROW_NUMBER`).
   * **Implementação de SCD Type 2:** O principal desafio técnico do projeto. A tabela de `driver_assignments` é versionada no tempo (`effective_start` e `effective_end`). A telemetria é cruzada temporalmente com essa dimensão para garantir que uma infração seja atribuída ao motorista que estava ao volante no exato milissegundo do evento.

3. **Gold Layer (Business Aggregates):**
   * Criação da `fact_telemetria` otimizada com `Z-ORDER BY (truck_id, data_hora)`.
   * Tabela agregada diária `agg_driver_performance_daily` que calcula KPIs de negócio:
     * **Tempo Ocioso:** Identificação de desperdício cruzando velocidade `0` com RPM em marcha lenta.
     * **Score de Condução:** Algoritmo de penalização baseado em contagem de infrações de velocidade, rotação excessiva e superaquecimento do motor.


## 🚨 Monitoramento e Alertas

Para garantir a qualidade dos dados (Data Quality) e a acionabilidade da operação, o pipeline executa validações pós-processamento utilizando rotinas SQL:
* **DQ Alerts:** Monitora falhas de integridade na Silver/Gold (ex: eventos de telemetria órfãos, onde o SCD Type 2 não encontrou motorista alocado no ERP).
* **Business Alerts:** Dispara alertas caso a média do *Score de Condução* de um motorista caia para níveis críticos (< 50) no fechamento diário.

## 🛠️ Stack Tecnológico
* **Databricks / Apache Spark:** Processamento distribuído e Auto Loader.
* **Delta Lake:** Formato de armazenamento (ACID transactions, Time Travel, Z-Ordering).
* **Databricks Workflows:** Orquestração de Jobs parametrizados (`job.yml`).
* **Python (Faker/Boto3):** Geradores de dados *stateful* para simulação de física realista.
* **Databricks CLI & Lakehouse Federation:** Gerenciamento de Secrets e virtualização de dados externos.

## 🚀 Como Executar o Projeto

**1. Configuração de Credenciais e Segurança**
O projeto não utiliza senhas expostas no código. Configure as credenciais do S3 e do gerador ERP via Databricks CLI no seu terminal:
```bash
databricks secrets create-scope --scope project_secrets
databricks secrets put --scope project_secrets --key aws_access_key
databricks secrets put --scope project_secrets --key aws_secret_key
databricks secrets put --scope project_secrets --key supabase_host
databricks secrets put --scope project_secrets --key supabase_port
databricks secrets put --scope project_secrets --key supabase_user
databricks secrets put --scope project_secrets --key supabase_password
```
**2. Preparação do S3 e Conexões (Unity Catalog)**
* **AWS S3:** Crie um bucket na sua conta AWS (ex: `fleetops-landing-zone`).
* **Unity Catalog (External Location):** No Databricks, crie uma *Storage Credential* com as permissões da AWS e, em seguida, crie um *External Location* apontando para o seu bucket. Isso é obrigatório para que o comando `CREATE EXTERNAL VOLUME` da camada Bronze funcione.
* **PostgreSQL (Lakehouse Federation):** Em **Catalog > Add > Connection**, crie uma conexão do tipo PostgreSQL. 
  **Importante:** O nome da conexão deve ser `con_supabase`, pois os notebooks da Bronze o referenciam.
  
**3. Execução e Validação do Pipeline (Simulando o SCD Type 2)**
Para que o pipeline demonstre o seu principal valor (a resolução de troca de motoristas no tempo), o fluxo de execução deve seguir a ordem cronológica abaixo:

* **Passo 3.1 (O Início do Turno):** Rode o notebook `scripts/supabase_erp_generator.ipynb` com o parâmetro `p_day = 1`. Isso alocará os motoristas iniciais nos caminhões.
* **Passo 3.2 (Gerando Tráfego):** Rode o notebook `scripts/s3_telemetry_generator.ipynb`. **Atenção:** Este script roda em um loop infinito enviando dados a cada 30 segundos. Deixe-o rodar por cerca de 2 ou 3 minutos para gerar uma volumetria inicial e, em seguida, **interrompa a execução manualmente**.
* **Passo 3.3 (Primeira Ingestão):** Rode o seu Job no Databricks (`00_setup/job.yml`) ou execute as camadas Bronze, Silver e Gold sequencialmente. Isso criará a base histórica (Estado A).
* **Passo 3.4 (A Troca de Motorista):** Volte ao notebook `scripts/supabase_erp_generator.ipynb` e rode-o com o parâmetro `p_day = 2`. Isso fará com que o sistema transacional troque o motorista de um dos caminhões.
* **Passo 3.5 (Tráfego do Novo Motorista):** Rode o `scripts/s3_telemetry_generator.ipynb` novamente por mais alguns minutos e depois interrompa. Os novos eventos de IoT agora pertencem ao novo motorista.
* **Passo 3.6 (O Teste do SCD2):** Rode o Job do Databricks pela segunda vez. A camada Silver fará o fechamento da janela de tempo do motorista antigo e abrirá a do novo. A camada Gold cruzará os eventos perfeitamente.

**4. Execução do Pipeline**
Utilize o arquivo `00_setup/job.yml` para importar o Workflow completo no Databricks, ou rode os notebooks das camadas `Bronze`, `Silver` e `Gold` de forma sequencial. O código já está preparado para validar e criar dinamicamente os schemas e volumes necessários durante a primeira execução.

**5. Configuração dos Alertas (Databricks SQL)**
Toda a configuração de *Thresholds* e *Schedules* dos alertas foi versionada como código na pasta `/alerts` utilizando arquivos `.dbalert.json`. A importação é nativa e simplificada:

1. Baixe os arquivos `.dbalert.json` disponíveis na pasta `/alerts` deste repositório.
2. No menu lateral do Databricks, acesse a aba **Workspace**.
3. Arraste e solte os arquivos JSON diretamente para dentro da sua pasta de trabalho.
4. O Databricks reconhecerá automaticamente os arquivos como Alertas. Basta abri-los, verificar a query conectada e ativá-los.
