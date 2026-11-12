"""
Lambda Backend for AWS Bedrock Enterprise RAG & BI Dashboard.
Handles:
  - GET  /kpis : Reads and aggregates financial and commercial KPIs from S3.
  - POST /chat : Executes RAG queries combining Knowledge Base retrieval (Amazon S3 Vectors)
                 and generation via Amazon Bedrock (Nova Lite / Claude).
"""

import csv
import io
import json
import logging
import os
import re
from typing import Any, Dict, List, Optional, Tuple

import boto3
from botocore.exceptions import ClientError

# Configure structured logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment configurations
AWS_REGION = os.environ.get("AWS_REGION", "us-east-2")
AWS_ACCOUNT_ID = os.environ.get("AWS_ACCOUNT_ID", "710280692169")
KNOWLEDGE_BASE_ID = os.environ.get("KNOWLEDGE_BASE_ID", "")
DATA_BUCKET_NAME = os.environ.get("DATA_BUCKET_NAME", "")
MODEL_ID = os.environ.get("MODEL_ID", "us.amazon.nova-lite-v1:0")
CORS_ALLOWED_ORIGIN = os.environ.get("CORS_ALLOWED_ORIGIN", "*")

# Global AWS clients initialized outside handler for connection reuse
s3_client = boto3.client("s3", region_name=AWS_REGION)
bedrock_agent_runtime = boto3.client("bedrock-agent-runtime", region_name=AWS_REGION)


def get_cors_headers() -> Dict[str, str]:
    """Standard CORS headers for HTTP API v2."""
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": CORS_ALLOWED_ORIGIN,
        "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Requested-With",
        "Access-Control-Max-Age": "300",
    }


def build_response(status_code: int, body: Any) -> Dict[str, Any]:
    """Builds a compliant HTTP API Gateway response dictionary."""
    return {
        "statusCode": status_code,
        "headers": get_cors_headers(),
        "body": json.dumps(body, ensure_ascii=False),
    }


def resolve_model_arn(model_identifier: str, region: str, account_id: str) -> str:
    """
    Resolves model ARN or inference profile ARN for Bedrock retrieve_and_generate.
    Accepts full ARNs, inference profile IDs (e.g. us.amazon.nova-lite-v1:0),
    or foundation model IDs (e.g. amazon.nova-lite-v1:0).
    """
    if model_identifier.startswith("arn:aws:bedrock:"):
        return model_identifier

    # Cross-region inference profile (starts with 'us.' or 'eu.')
    if model_identifier.startswith("us.") or model_identifier.startswith("eu."):
        # System-defined or account-defined inference profile
        return f"arn:aws:bedrock:{region}:{account_id}:inference-profile/{model_identifier}"

    # Default foundation model ARN
    return f"arn:aws:bedrock:{region}::foundation-model/{model_identifier}"


def load_kpis_from_s3() -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    Retrieves and parses the KPI CSV file from the private S3 data bucket.
    Computes executive metrics and time series for dashboard charts.
    """
    csv_key = "kpis/faturamento_2026.csv"
    logger.info("Fetching KPI dataset from s3://%s/%s", DATA_BUCKET_NAME, csv_key)

    try:
        response = s3_client.get_object(Bucket=DATA_BUCKET_NAME, Key=csv_key)
        content = response["Body"].read().decode("utf-8")
    except ClientError as e:
        logger.error("Failed to read S3 object: %s", str(e))
        raise

    reader = csv.DictReader(io.StringIO(content))
    rows: List[Dict[str, Any]] = []

    total_faturamento = 0.0
    total_meta = 0.0
    total_novos_clientes = 0
    total_churn_sum = 0.0
    total_ticket_medio_sum = 0.0

    for r in reader:
        try:
            mes_num = int(r["mes"])
            mes_nome = r["mes_nome"]
            ano = int(r["ano"])
            faturamento = float(r["faturamento_bruto"])
            meta = float(r["meta"])
            atingimento = float(r["atingimento_pct"])
            novos = int(r["novos_clientes"])
            churn = float(r["churn_rate_pct"])
            ticket = float(r["ticket_medio_brl"])
            cac = float(r.get("cac_brl", 0.0))
            ltv = float(r.get("ltv_brl", 0.0))

            total_faturamento += faturamento
            total_meta += meta
            total_novos_clientes += novos
            total_churn_sum += churn
            total_ticket_medio_sum += ticket

            rows.append({
                "mes": mes_num,
                "mes_nome": mes_nome,
                "ano": ano,
                "faturamento_bruto": faturamento,
                "meta": meta,
                "atingimento_pct": atingimento,
                "novos_clientes": novos,
                "churn_rate_pct": churn,
                "ticket_medio_brl": ticket,
                "cac_brl": cac,
                "ltv_brl": ltv,
            })
        except (ValueError, KeyError) as parse_err:
            logger.warning("Skipping malformed CSV row %s: %s", r, parse_err)
            continue

    n = len(rows)
    churn_medio = round(total_churn_sum / n, 2) if n > 0 else 0.0
    ticket_medio_geral = round(total_faturamento / total_novos_clientes, 2) if total_novos_clientes > 0 else 0.0
    atingimento_total_pct = round((total_faturamento / total_meta) * 100, 2) if total_meta > 0 else 0.0

    # Growth rate between first and latest month
    crescimento_acumulado_pct = 0.0
    if n >= 2 and rows[0]["faturamento_bruto"] > 0:
        crescimento_acumulado_pct = round(
            ((rows[-1]["faturamento_bruto"] - rows[0]["faturamento_bruto"]) / rows[0]["faturamento_bruto"]) * 100, 2
        )

    summary = {
        "periodo": f"Janeiro a {rows[-1]['mes_nome'] if rows else ''} de 2026",
        "meses_computados": n,
        "faturamento_total_brl": round(total_faturamento, 2),
        "meta_total_brl": round(total_meta, 2),
        "atingimento_global_pct": atingimento_total_pct,
        "total_novos_clientes": total_novos_clientes,
        "ticket_medio_brl": ticket_medio_geral,
        "churn_medio_pct": churn_medio,
        "crescimento_acumulado_pct": crescimento_acumulado_pct,
        "ultimo_mes": rows[-1] if rows else None,
    }

    return rows, summary


def handle_get_kpis() -> Dict[str, Any]:
    """Handles GET /kpis endpoint."""
    try:
        rows, summary = load_kpis_from_s3()

        # Build chart-ready series
        chart_data = {
            "labels": [r["mes_nome"] for r in rows],
            "faturamento": [r["faturamento_bruto"] for r in rows],
            "meta": [r["meta"] for r in rows],
            "novos_clientes": [r["novos_clientes"] for r in rows],
            "churn_rate": [r["churn_rate_pct"] for r in rows],
            "ticket_medio": [r["ticket_medio_brl"] for r in rows],
        }

        # Formatted card statistics
        cards = [
            {
                "id": "faturamento_total",
                "titulo": "Faturamento Acumulado (YTD)",
                "valor": f"R$ {summary['faturamento_total_brl']:,.2f}".replace(",", "X").replace(".", ",").replace("X", "."),
                "badge": f"{summary['atingimento_global_pct']}% da Meta",
                "badge_tipo": "sucesso" if summary["atingimento_global_pct"] >= 100 else "alerta",
                "icone": "dollar-sign",
            },
            {
                "id": "ticket_medio",
                "titulo": "Ticket Médio Enterprise",
                "valor": f"R$ {summary['ticket_medio_brl']:,.2f}".replace(",", "X").replace(".", ",").replace("X", "."),
                "badge": "+12.4% vs 2025",
                "badge_tipo": "sucesso",
                "icone": "trending-up",
            },
            {
                "id": "novos_clientes",
                "titulo": "Novos Clientes Adquiridos",
                "valor": str(summary["total_novos_clientes"]),
                "badge": f"Q3 Recorde (+{summary['crescimento_acumulado_pct']}%)",
                "badge_tipo": "sucesso",
                "icone": "users",
            },
            {
                "id": "churn_medio",
                "titulo": "Churn Rate Médio",
                "valor": f"{summary['churn_medio_pct']}%",
                "badge": "Benchmark Setor 2.1%",
                "badge_tipo": "sucesso",
                "icone": "shield-check",
            },
        ]

        payload = {
            "status": "success",
            "summary": summary,
            "chart_data": chart_data,
            "cards": cards,
            "rows": rows,
        }
        return build_response(200, payload)

    except Exception as exc:
        logger.exception("Error processing /kpis: %s", exc)
        return build_response(500, {"status": "error", "message": f"Erro ao processar KPIs: {str(exc)}"})


def handle_post_chat(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handles POST /chat endpoint.
    Performs Bedrock retrieve_and_generate against S3 Vectors Knowledge Base,
    enriching the query context with structured financial facts.
    """
    body_raw = event.get("body", "{}")
    if event.get("isBase64Encoded", False):
        import base64
        body_raw = base64.b64decode(body_raw).decode("utf-8")

    try:
        body = json.loads(body_raw) if isinstance(body_raw, str) else body_raw
    except json.JSONDecodeError:
        return build_response(400, {"status": "error", "message": "Corpo da requisição deve ser um JSON válido."})

    question = (body.get("question") or "").strip()
    session_id = body.get("session_id")

    if not question:
        return build_response(400, {"status": "error", "message": "O campo 'question' é obrigatório."})

    logger.info("Executing RAG chat query: '%s' (session_id=%s)", question, session_id)

    # Pre-fetch KPI summary to augment context if question relates to numbers, revenue or goals
    kpi_context_snippet = ""
    try:
        _, summary = load_kpis_from_s3()
        kpi_context_snippet = (
            f"[FATOS_FINANCEIROS_YTD_2026: Faturamento total acumulado: R$ {summary['faturamento_total_brl']:,.2f}; "
            f"Meta total: R$ {summary['meta_total_brl']:,.2f} ({summary['atingimento_global_pct']}% atingido); "
            f"Novos clientes: {summary['total_novos_clientes']}; Ticket médio geral: R$ {summary['ticket_medio_brl']:,.2f}; "
            f"Churn médio: {summary['churn_medio_pct']}%; Crescimento Jan-Out: {summary['crescimento_acumulado_pct']}%]\n\n"
        )
    except Exception as kpi_err:
        logger.warning("Could not append KPI context snippet: %s", kpi_err)

    # Prompt Template to instruct Bedrock foundation model
    system_prompt = (
        "Você é o Assistente Executivo e Analista de IA Corporativo da ApexCloud Enterprise Solutions. "
        "Responda à pergunta do usuário de forma profissional, altamente analítica e em Português do Brasil.\n"
        "Regras obrigatórias:\n"
        "1. Baseie sua resposta estritamente nas informações dos documentos recuperados da Knowledge Base e nos fatos financeiros fornecidos.\n"
        "2. Ao citar políticas de desconto, especifique detalhadamente as faixas percentuais e quem tem autoridade para aprovação.\n"
        "3. Seja claro, conciso e use marcadores em tópicos quando listar requisitos ou regras de negócio.\n"
        "4. Caso a resposta não conste nas fontes, informe cordialmente que a informação não está contemplada na base corporativa atual.\n\n"
        f"Contexto dos Fatos Corporativos:\n{kpi_context_snippet}"
        "Trechos Recuperados da Base de Conhecimento:\n$search_results$\n\n"
        "Pergunta do Colaborador: $query$\n\n"
        "Resposta Estruturada:"
    )

    # Resolve Model ARN
    primary_model_arn = resolve_model_arn(MODEL_ID, AWS_REGION, AWS_ACCOUNT_ID)
    fallback_model_arn = f"arn:aws:bedrock:{AWS_REGION}::foundation-model/amazon.nova-lite-v1:0"

    rag_config = {
        "type": "KNOWLEDGE_BASE",
        "knowledgeBaseConfiguration": {
            "knowledgeBaseId": KNOWLEDGE_BASE_ID,
            "modelArn": primary_model_arn,
            "generationConfiguration": {
                "promptTemplate": {
                    "textPromptTemplate": system_prompt
                }
            },
        },
    }

    req_params: Dict[str, Any] = {
        "input": {"text": question},
        "retrieveAndGenerateConfiguration": rag_config,
    }
    if session_id:
        req_params["sessionId"] = session_id

    try:
        response = bedrock_agent_runtime.retrieve_and_generate(**req_params)
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "")
        error_msg = e.response.get("Error", {}).get("Message", "")
        logger.warning("retrieve_and_generate failed with primary model (%s: %s). Trying fallback...", error_code, error_msg)

        # Try fallback model if cross-region inference profile ARN caused an issue
        try:
            req_params["retrieveAndGenerateConfiguration"]["knowledgeBaseConfiguration"]["modelArn"] = fallback_model_arn
            response = bedrock_agent_runtime.retrieve_and_generate(**req_params)
        except Exception as fallback_exc:
            logger.exception("Fallback also failed: %s", fallback_exc)
            return build_response(500, {
                "status": "error",
                "message": f"Erro na consulta do Bedrock: {error_msg or str(fallback_exc)}",
                "details": "Verifique se a Knowledge Base concluiu o job de ingestão de dados.",
            })

    output_text = response.get("output", {}).get("text", "")
    returned_session_id = response.get("sessionId", "")

    # Extract source citations
    citations: List[Dict[str, Any]] = []
    raw_citations = response.get("citations", [])
    for c in raw_citations:
        retrieved_refs = c.get("retrievedReferences", [])
        for ref in retrieved_refs:
            location = ref.get("location", {})
            s3_uri = location.get("s3Location", {}).get("uri", "")
            snippet = ref.get("content", {}).get("text", "")
            source_file = s3_uri.split("/")[-1] if "/" in s3_uri else s3_uri

            citations.append({
                "source_file": source_file,
                "s3_uri": s3_uri,
                "snippet": snippet[:280] + ("..." if len(snippet) > 280 else ""),
            })

    payload = {
        "status": "success",
        "answer": output_text,
        "session_id": returned_session_id,
        "citations": citations,
        "model_used": MODEL_ID,
    }
    return build_response(200, payload)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main AWS Lambda entrypoint router for HTTP API Gateway v2."""
    logger.info("Received event: %s", json.dumps(event, default=str))

    # Determine HTTP Method and Path
    http_context = event.get("requestContext", {}).get("http", {})
    method = http_context.get("method") or event.get("httpMethod", "GET")
    raw_path = event.get("rawPath") or event.get("path", "/")

    # Normalize method and path
    method = method.upper()
    path = re.sub(r"/+", "/", raw_path).rstrip("/")
    if not path:
        path = "/"

    logger.info("Routing request: %s %s", method, path)

    # CORS Preflight
    if method == "OPTIONS":
        return {
            "statusCode": 204,
            "headers": get_cors_headers(),
            "body": "",
        }

    # Route matching
    if (method == "GET" and path.endswith("/kpis")) or (method == "GET" and path == "/"):
        return handle_get_kpis()

    if method == "POST" and path.endswith("/chat"):
        return handle_post_chat(event)

    # 404 Route Not Found
    return build_response(404, {
        "status": "error",
        "message": f"Rota não encontrada: {method} {raw_path}",
        "available_routes": ["GET /kpis", "POST /chat", "OPTIONS /*"],
    })

