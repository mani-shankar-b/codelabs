# CK-Agent Python Port: Detailed Implementation Plan

## Executive Summary

This plan outlines the porting of Java CK-Agent customizations to Python. The Java agent transforms OpenTelemetry spans into lightweight "CK spans" and emits metrics instead of exporting full span objects. The plan covers component mapping, SDK integration points, instrumentation modifications, and architectural approach comparison.

## 1. CK Components to Create (Apples-to-Apples Mapping)

### 1.1 Core Span Components

#### 1.1.1 `CKSpan` Class

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/span/CKSpan.java`

**Python Equivalent**: Create `ck_agent/span/ck_span.py`

- **Purpose**: Lightweight span implementation replacing OpenTelemetry's `Span`
- **Implements**: `opentelemetry.trace.Span` interface (or minimal subset)
- **Key Features**:
  - Minimal data storage (attributes, timestamps, status, span kind)
  - No events, links, or full trace context
  - Implements `ReadableSpan` for compatibility with `SpanProcessor`
- **Dependencies**: 
  - `opentelemetry.trace.Span`
  - `opentelemetry.sdk.trace.ReadableSpan`
  - Custom `CKSpanAttributes` class

#### 1.1.2 `CKSpanAttributes` Class

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/span/CKSpanAttributes.java`

**Python Equivalent**: Create `ck_agent/span/ck_span_attributes.py`

- **Purpose**: Custom `AttributesBuilder` and `Attributes` implementation for `CKSpan`
- **Key Features**:
  - Efficient attribute storage (dict-based)
  - Bounded attribute count
  - Type-safe attribute access

### 1.2 Span Provider & Processor Components

#### 1.2.1 `CKSpanProvider` Interface

**Java Location**: `ck-agent/java/bootstrap/src/main/java/com/ck/agent/bootstrap/platform/span/CKSpanProvider.java`

**Python Equivalent**: Create `ck_agent/span/ck_span_provider.py`

- **Purpose**: Interface/ABC defining methods for `CKSpan` creation and lifecycle
- **Methods**:
  - `get_span_instance() -> Span`
  - `set_span_kind(span: Span, span_kind: SpanKind)`
  - `start(span: Span, start_time: int)`
  - `get_attributes_builder(span: Span) -> AttributesBuilder`
  - `get_attributes(span: Span) -> Attributes`
  - `trigger_on_start(context: Context, span: Span) -> Context`
  - `is_valid_instance(span: Span) -> bool`
  - `trigger_on_end(span: Span)`

#### 1.2.2 `CKGraphSpanProvider` Implementation

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/span/CKGraphSpanProvider.java`

**Python Equivalent**: Create `ck_agent/span/ck_graph_span_provider.py`

- **Purpose**: Concrete implementation of `CKSpanProvider`
- **Key Features**:
  - Creates `CKSpan` instances
  - Triggers `CKGraphSpanProcessor` on span end
  - Manages span lifecycle

#### 1.2.3 `CKSpanProcessors` Registry

**Java Location**: `ck-agent/java/bootstrap/src/main/java/com/ck/agent/bootstrap/platform/span/CKSpanProcessors.java`

**Python Equivalent**: Create `ck_agent/span/ck_span_processors.py`

- **Purpose**: Static/global registry for `CKSpanProvider` instance
- **Pattern**: Singleton or module-level variable
- **Usage**: Accessed by instrumentation code to get current provider

### 1.3 Graph Processing Components

#### 1.3.1 `CKGraphSpanProcessor`

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/processors/CKGraphSpanProcessor.java`

**Python Equivalent**: Create `ck_agent/processors/ck_graph_span_processor.py`

- **Purpose**: `SpanProcessor` that converts `CKSpan` to Graph Path Elements (GPE)
- **Implements**: `opentelemetry.sdk.trace.SpanProcessor`
- **Key Features**:
  - `on_end(span)` method converts span to GPE
  - Calls `SGPNProcessor` for span-to-GPE mapping
  - Integrates with graph path building system

#### 1.3.2 `SGPNProcessor` (Span-to-GPE Mapper)

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/processors/SGPNProcessor.java`

**Python Equivalent**: Create `ck_agent/processors/sgpn_processor.py`

- **Purpose**: Maps `CKSpan` attributes to specific `GraphPathElement` types
- **Key Features**:
  - Optimized lookup tables (by SpanKind, DB system, messaging system, etc.)
  - Library-specific mappers (Elasticsearch, MongoDB, Kafka, HTTP, gRPC, etc.)
  - ServiceLoader pattern → Python entry_points or plugin registry

#### 1.3.3 Graph Path Element Mappers

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/processors/mapper/`

**Python Equivalent**: Create `ck_agent/processors/mapper/` directory

- **Mapper Types**:
  - `ElasticsearchSGPEMapper`
  - `MongoDbSGPEMapper`
  - `DynamoDBSGPEMapper`
  - `RedisSGPEMapper`
  - `SqlSGPEMapper`
  - `KafkaConsumerGPEMapper` / `KafkaProducerBEMapper`
  - `PulsarConsumerGPEMapper` / `PulsarProducerBEMapper`
  - `HttpBridgeSGPEMapper`
  - `GrpcClientBridgeMapper` / `GrpcServerMapper`
  - `AwsMessagingBridgeSGPEMapper`
  - `GCPBigtableSGPEMapper`
- **Base Class**: `SpanToGPEMapper` ABC/interface

### 1.4 Metrics Components

#### 1.4.1 `GraphPathOTLPMetrics`

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/custom/graph/GraphPathOTLPMetrics.java`

**Python Equivalent**: Create `ck_agent/metrics/graph_path_otlp_metrics.py`

- **Purpose**: Converts graph path data into OTLP metrics
- **Key Features**:
  - Latency histograms (p50, p90, p95, p99) using HDRHistogram equivalent
  - Throughput counters
  - Error counters
  - ObservableGauge for percentile export
- **Dependencies**:
  - `opentelemetry.sdk.metrics.Meter`
  - `opentelemetry.sdk.metrics.Histogram`
  - `opentelemetry.sdk.metrics.Counter`
  - `opentelemetry.sdk.metrics.ObservableGauge`
  - Python HDRHistogram library (e.g., `hdrhistogram` package)

#### 1.4.2 `MetricSyncManager`

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/custom/platform/scheduled/MetricSyncManager.java`

**Python Equivalent**: Create `ck_agent/metrics/metric_sync_manager.py`

- **Purpose**: Manages OTLP gRPC metric export
- **Key Features**:
  - Creates and configures `SdkMeterProvider`
  - Sets up `PeriodicExportingMetricReader`
  - Conditional metric collection (threshold-based)
  - Resource creation with app metadata
- **Dependencies**:
  - `opentelemetry.sdk.metrics.SdkMeterProvider`
  - `opentelemetry.sdk.metrics.export.PeriodicExportingMetricReader`
  - `opentelemetry.exporter.otlp.proto.grpc.metric_exporter.OtlpGrpcMetricExporter`

### 1.5 Context Propagation Components

#### 1.5.1 `CKRoutePropagator` (Custom TextMapPropagator)

**Java Location**: `ck-agent/java/custom/src/main/java/com.codekarma.agent.propagator/P.java`

**Python Equivalent**: Create `ck_agent/propagator/ck_route_propagator.py`

- **Purpose**: Custom propagator for `ck-route` header instead of standard trace context
- **Implements**: `opentelemetry.propagators.textmap.TextMapPropagator`
- **Key Features**:
  - `inject(context, carrier, setter)` - injects `ck-route` header
  - `extract(context, carrier, getter)` - extracts `ck-route` header
  - Handles gRPC-specific extraction
  - Conditional injection based on instrumentation status
- **Constants**: `CK_ROUTE_KEY = "ck-route"`, `CK_GLITCH_KEY`

#### 1.5.2 Context Helpers

**Java Location**: `ck-agent/java/bootstrap/src/main/java/com/ck/agent/bootstrap/common/ContextHelpers.java`

**Python Equivalent**: Create `ck_agent/common/context_helpers.py`

- **Purpose**: Utilities for managing graph path in OpenTelemetry Context
- **Key Functions**:
  - `get_path_from_context(context: Context) -> Optional[str]`
  - `set_path_key_path_in_context(context: Context, path_key: str) -> Context`
  - Context key management for graph path storage

### 1.6 Configuration & Auto-Configuration Components

#### 1.6.1 `CKAutoConfigurationCustomizer`

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/custom/CKAutoConfigurationCustomizerProvider.java`

**Python Equivalent**: Create `ck_agent/config/ck_auto_configuration.py`

- **Purpose**: Disables default OpenTelemetry SDK components and registers custom ones
- **Key Features**:
  - Noop span processors/exporters
  - Disabled default meter provider
  - Custom propagator registration
  - Custom span processor registration
- **Integration Point**: OpenTelemetry Python SDK configurator system
- **Dependencies**: `opentelemetry.sdk._configuration._BaseConfigurator`

#### 1.6.2 `CKNoopSpanProcessor`

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/processors/CKNoopSpanProcessor.java`

**Python Equivalent**: Create `ck_agent/processors/ck_noop_span_processor.py`

- **Purpose**: No-op span processor to suppress default span export
- **Implements**: `opentelemetry.sdk.trace.SpanProcessor`
- **Methods**: All methods are no-ops

#### 1.6.3 `CKNoopExporters`

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/custom/CKNoopExporters.java`

**Python Equivalent**: Create `ck_agent/exporters/ck_noop_exporters.py`

- **Purpose**: No-op exporters for spans, metrics, logs
- **Implements**: 
  - `opentelemetry.sdk.trace.SpanExporter`
  - `opentelemetry.sdk.metrics.export.MetricExporter`
  - `opentelemetry.sdk.logs.LogExporter` (if needed)

### 1.7 Graph Path Building Components

#### 1.7.1 `GraphPathInfo` / `GPI` (Graph Path Interface)

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/custom/platform/GraphPathInfo.java` and `ck-agent/java/bootstrap/src/main/java/com/ck/agent/bootstrap/platform/graph/GPI.java`

**Python Equivalent**: Create `ck_agent/graph/graph_path_info.py` and `ck_agent/graph/gpi.py`

- **Purpose**: Core graph path building and management
- **Key Features**:
  - Graph path element creation (`GPI.c()`)
  - Path hash generation (`GPI.a()`)
  - Path key management
  - Graph path node wrapping

#### 1.7.2 Graph Path Element Types

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/commons/graph/` (referenced)

**Python Equivalent**: Create `ck_agent/graph/graph_path_elements.py`

- **Types**:
  - `HTTPServiceGPE`
  - `ExternalClientGPE`
  - `DatabaseGPE`
  - `MessagingGPE`
  - etc.

### 1.8 Initialization Components

#### 1.8.1 `CKAgentListener` / Initialization Hook

**Java Location**: `ck-agent/java/custom/src/main/java/com/codekarma/agent/custom/CKAgentListener.java`

**Python Equivalent**: Create `ck_agent/init/ck_agent_initializer.py`

- **Purpose**: Initializes CK components after SDK setup
- **Key Initialization**:
  - `CKSpanProcessors.set_ck_span_provider(CKGraphSpanProvider())`
  - `GraphPathInfo.init()`
  - `MetricSyncManager.initialize()`
  - Other component initialization
- **Integration Point**: OpenTelemetry Python SDK initialization hooks or distro entry point

## 2. Python SDK Hooks & Adjustments

### 2.1 Span Creation Interception

#### 2.1.1 Problem Statement

In Java, the modified `Instrumenter` class in the bootstrap classloader intercepts all span creation. Python doesn't have an equivalent bootstrap mechanism, so we need alternative approaches.

#### 2.1.2 Approach A: Custom TracerProvider (Recommended)

**Location**: Create `ck_agent/sdk/ck_tracer_provider.py`

**Implementation**:

- Subclass `opentelemetry.sdk.trace.TracerProvider`
- Override `get_tracer()` to return custom `CKTracer`
- `CKTracer` overrides `start_span()` to create `CKSpan` instead of regular spans
- Register custom `TracerProvider` via SDK configurator

**Code Structure**:

```python
class CKTracerProvider(TracerProvider):
    def get_tracer(self, name, version=None, schema_url=None):
        return CKTracer(name, version, schema_url, self._resource, ...)

class CKTracer(Tracer):
    def start_span(self, name, context=None, kind=SpanKind.INTERNAL, ...):
        # Check if should create CKSpan
        if should_create_ck_span(kind, context):
            span = ck_span_provider.get_span_instance()
            # Configure span...
            return span
        # Fallback to regular span if needed
```

**Integration Point**: `opentelemetry.sdk._configuration._BaseConfigurator._configure_tracer_provider()`

#### 2.1.3 Approach B: SpanProcessor.on_start() Interception

**Location**: `ck_agent/processors/ck_span_interceptor_processor.py`

**Implementation**:

- Create a `SpanProcessor` that intercepts `on_start()`
- Replace the span in context with `CKSpan`
- **Limitation**: This happens after span creation, so we can't prevent regular span creation entirely

**Trade-off**: Less control but easier to implement

#### 2.1.4 Approach C: Monkey-Patch Tracer.start_span()

**Location**: `ck_agent/sdk/tracer_patch.py`

**Implementation**:

- Monkey-patch `opentelemetry.sdk.trace.Tracer.start_span()` at import time
- Replace with custom implementation that creates `CKSpan`
- **Risk**: Fragile, may break with SDK updates

**Trade-off**: Maximum control but high maintenance burden

### 2.2 Span Suppression & Noop Components

#### 2.2.1 Disable Default Span Exporters

**Location**: `ck_agent/config/ck_auto_configuration.py`

**Implementation**:

- In SDK configurator, set `OTEL_TRACES_EXPORTER=none` or register noop exporters
- Override `_configure_span_processors()` to return `[CKNoopSpanProcessor()]`
- Override `_configure_span_exporters()` to return `[CKNoopSpanExporter()]`

**Integration Point**: `opentelemetry.sdk._configuration._OTelSDKConfigurator`

#### 2.2.2 Disable Default Metrics

**Location**: `ck_agent/config/ck_auto_configuration.py`

**Implementation**:

- Override `_configure_meter_provider()` to return disabled meter provider
- Or configure meter provider with no metric readers

### 2.3 Custom Propagator Registration

#### 2.3.1 Register CKRoutePropagator

**Location**: `ck_agent/config/ck_auto_configuration.py`

**Implementation**:

- Override `_configure_propagators()` to return `[CKRoutePropagator()]`
- Or use `opentelemetry.propagators.set_global_textmap()` if available
- Ensure it's registered before any instrumentation runs

**Integration Point**: `opentelemetry.sdk._configuration._OTelSDKConfigurator._configure_propagators()`

### 2.4 Metrics SDK Integration

#### 2.4.1 Custom MeterProvider Setup

**Location**: `ck_agent/metrics/metric_sync_manager.py`

**Implementation**:

- Create `SdkMeterProvider` with custom `PeriodicExportingMetricReader`
- Configure OTLP gRPC exporter with CK-specific headers
- Register `GraphPathOTLPMetrics` observable gauges
- Set up conditional metric collection based on threshold

**Integration Point**:

- `opentelemetry.sdk.metrics.SdkMeterProvider`
- `opentelemetry.sdk.metrics.export.PeriodicExportingMetricReader`
- `opentelemetry.exporter.otlp.proto.grpc.metric_exporter.OtlpGrpcMetricExporter`

### 2.5 SDK Configurator Integration

#### 2.5.1 Custom Configurator Class

**Location**: `ck_agent/config/ck_sdk_configurator.py`

**Implementation**:

- Subclass `opentelemetry.sdk._configuration._BaseConfigurator` or `_OTelSDKConfigurator`
- Override methods:
  - `_configure_tracer_provider()` → return `CKTracerProvider`
  - `_configure_span_processors()` → return `[CKGraphSpanProcessor, CKNoopSpanProcessor]`
  - `_configure_span_exporters()` → return `[CKNoopSpanExporter]`
  - `_configure_meter_provider()` → return disabled or custom meter provider
  - `_configure_propagators()` → return `[CKRoutePropagator]`

#### 2.5.2 Entry Point Registration

**Location**: `ck_agent/setup.py` or `pyproject.toml`

**Implementation**:

- Register configurator as entry point: `opentelemetry_sdk_configurator`
- Or use environment variable: `OTEL_SDK_CONFIGURATOR=ck_agent.config.ck_sdk_configurator:CKSDKConfigurator`

**Pattern**:

```python
# setup.py
entry_points={
    "opentelemetry_sdk_configurator": [
        "ck_agent = ck_agent.config.ck_sdk_configurator:CKSDKConfigurator",
    ],
}
```

## 3. Python Instrumentation Library Modifications

### 3.1 Instrumentation Modification Strategy

#### 3.1.1 Problem Statement

Java CK-Agent modifies instrumentation libraries in `ck-agent/java/instrumentation/` to inject custom code (e.g., `DispatcherServeletInstrumentationHelper` for Spring). Python instrumentations use monkey-patching, so modifications are different.

#### 3.1.2 Approach: Wrapper/Helper Functions

Instead of modifying instrumentation source code directly, create helper modules that instrumentation libraries can call.

**Location**: Create `ck_agent/instrumentation/helpers/` directory

**Pattern**: Each instrumentation that needs custom logic gets a helper module:

- `ck_agent/instrumentation/helpers/flask_helper.py`
- `ck_agent/instrumentation/helpers/django_helper.py`
- `ck_agent/instrumentation/helpers/grpc_helper.py`
- `ck_agent/instrumentation/helpers/kafka_helper.py`
- etc.

### 3.2 Specific Instrumentation Modifications Needed

#### 3.2.1 HTTP Server Instrumentations (Flask, Django, FastAPI, Starlette, WSGI, ASGI)

**Java Reference**: `ck-agent/java/instrumentation/spring/spring_v2/springwebv2/DispatcherServeletInstrumentationHelper.java`

**Python Modifications**:

- **Location**: Modify or wrap:
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-flask/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-django/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-fastapi/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-starlette/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-wsgi/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-asgi/`

**Changes Needed**:

1. **Request Start Hook**: Extract `http.route` attribute, create `HTTPServiceGPE`, build graph path
2. **Context Path Key Management**: 

   - Extract `ck-route` header from incoming request
   - Create new path key if external request
   - Store path key in context

3. **Response End Hook**: Ensure path key is properly propagated

**Helper Function Pattern**:

```python
# ck_agent/instrumentation/helpers/http_server_helper.py
def handle_http_request_start(environ, route_info):
    """Called at HTTP request start"""
    incoming_path = extract_ck_route_header(environ)
    if not incoming_path:
        incoming_path = get_external_incoming_path(environ)
    
    graph_path_element = HTTPServiceGPE(
        method=environ.get('REQUEST_METHOD'),
        route=route_info
    )
    graph_path_node = GPI.create(incoming_path, graph_path_element)
    new_path_hash = GPI.get_path_hash(graph_path_node, is_start=True)
    set_path_key_in_context(new_path_hash)
```

**Integration**: Modify instrumentation's request hook to call helper

#### 3.2.2 gRPC Instrumentation

**Java Reference**: `ck-agent/java/custom/src/main/java/com.codekarma.agent.propagator/P.java` (gRPC handling in `extract()`)

**Python Modifications**:

- **Location**: `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-grpc/`

**Changes Needed**:

1. **Server Interceptor**: Extract `ck-route` header and `x-client-id` from gRPC metadata
2. **Context Setup**: Handle gRPC method name for path building
3. **Client Interceptor**: Inject `ck-route` header in outgoing requests

**Helper Function**:

```python
# ck_agent/instrumentation/helpers/grpc_helper.py
def handle_grpc_request(metadata, method_name, context):
    """Handle gRPC server request"""
    ck_route = extract_ck_route_from_metadata(metadata)
    client_id = extract_client_id_from_metadata(metadata)
    return process_grpc_request(ck_route, client_id, method_name, context)
```

#### 3.2.3 Kafka Instrumentation

**Java Reference**: `ck-agent/java/instrumentation/kafka/kafka-overrides/`

**Python Modifications**:

- **Location**: 
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-kafka-python/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-confluent-kafka/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-aiokafka/`

**Changes Needed**:

1. **Consumer**: Extract `ck-route` from message headers, create `KafkaConsumerGPE`
2. **Producer**: Inject `ck-route` in message headers, create `KafkaProducerGPE`

#### 3.2.4 Database Instrumentations (SQLAlchemy, DBAPI, psycopg, etc.)

**Java Reference**: `ck-agent/java/instrumentation/jdbc/`

**Python Modifications**:

- **Location**: 
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-sqlalchemy/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-dbapi/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-psycopg2/`
  - etc.

**Changes Needed**:

1. **Span-to-GPE Mapping**: Use `SqlSGPEMapper` to convert database spans to GPE
2. **Attribute Extraction**: Ensure database system, connection string, etc. are captured

#### 3.2.5 Redis Instrumentation

**Java Reference**: `ck-agent/java/instrumentation/redis/`

**Python Modifications**:

- **Location**: `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-redis/`

**Changes Needed**:

1. **Span-to-GPE Mapping**: Use `RedisSGPEMapper`

#### 3.2.6 MongoDB Instrumentation

**Java Reference**: `ck-agent/java/instrumentation/mongodb/`

**Python Modifications**:

- **Location**: `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-pymongo/`

**Changes Needed**:

1. **Span-to-GPE Mapping**: Use `MongoDbSGPEMapper`

#### 3.2.7 Elasticsearch Instrumentation

**Java Reference**: `ck-agent/java/instrumentation/elasticsearch/`

**Python Modifications**:

- **Location**: `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-elasticsearch/`

**Changes Needed**:

1. **Span-to-GPE Mapping**: Use `ElasticsearchSGPEMapper`

#### 3.2.8 HTTP Client Instrumentations (requests, urllib3, httpx)

**Java Reference**: HTTP client handling in various instrumentations

**Python Modifications**:

- **Location**:
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-requests/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-urllib3/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-httpx/`

**Changes Needed**:

1. **Header Injection**: Inject `ck-route` header in outgoing requests
2. **Span-to-GPE Mapping**: Use `HttpBridgeSGPEMapper` for external client spans

#### 3.2.9 AWS SDK Instrumentations (boto3, botocore)

**Java Reference**: `ck-agent/java/instrumentation/aws/`

**Python Modifications**:

- **Location**:
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-botocore/`
  - `opentelemetry-python-contrib/instrumentation/opentelemetry-instrumentation-boto3sqs/`

**Changes Needed**:

1. **SQS**: Use `AwsMessagingBridgeSGPEMapper`
2. **DynamoDB**: Use `DynamoDBSGPEMapper`
3. **SNS**: Handle messaging spans

### 3.3 Instrumentation Modification Pattern

#### 3.3.1 Fork vs. Patch vs. Wrapper

**Option A: Fork opentelemetry-python-contrib**

- Create `ck-opentelemetry-python-contrib` with all modifications
- **Pros**: Full control, isolated changes
- **Cons**: Maintenance burden, need to sync with upstream

**Option B: Monkey-Patch Instrumentations**

- Patch instrumentation classes at runtime
- **Pros**: No fork needed, easier updates
- **Cons**: Fragile, may break with updates

**Option C: Wrapper/Helper Pattern (Recommended)**

- Keep OSS instrumentations unchanged
- Create helper modules that instrumentations call
- Use instrumentation hooks (request_hook, response_hook) where available
- For instrumentations without hooks, create wrapper instrumentations
- **Pros**: Minimal changes, easier maintenance
- **Cons**: Some instrumentations may not support hooks

#### 3.3.2 Implementation Strategy for Option C

1. **Create Helper Modules**: `ck_agent/instrumentation/helpers/`
2. **Create Wrapper Instrumentations**: `ck_agent/instrumentation/wrappers/`

   - Wrapper instrumentations that monkey-patch the same libraries
   - Call helpers at appropriate points
   - Can coexist with OSS instrumentations or replace them

3. **Use Instrumentation Hooks**: Where OSS instrumentations support hooks, configure them to call helpers
4. **Environment-Based Selection**: Use environment variables or config to choose between OSS and CK instrumentations

### 3.4 Hook Availability Analysis for Wrapper/Helper Pattern

#### 3.4.1 Comprehensive Hook Support Assessment

Based on analysis of `opentelemetry-python-contrib` instrumentations, here is the hook availability breakdown:

**Instrumentations WITH Full Hook Support (Can use helper pattern 100%)**:

1. **HTTP Server Instrumentations** (100% hook support):

   - `opentelemetry-instrumentation-flask`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-django`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-fastapi`: `server_request_hook`, `client_request_hook`, `client_response_hook` ✅
   - `opentelemetry-instrumentation-starlette`: `server_request_hook`, `client_request_hook`, `client_response_hook` ✅
   - `opentelemetry-instrumentation-wsgi`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-asgi`: `server_request_hook`, `client_request_hook`, `client_response_hook` ✅
   - `opentelemetry-instrumentation-tornado`: `server_request_hook`, `client_request_hook`, `client_response_hook` ✅
   - `opentelemetry-instrumentation-falcon`: hooks available ✅
   - `opentelemetry-instrumentation-pyramid`: hooks available ✅

2. **HTTP Client Instrumentations** (100% hook support):

   - `opentelemetry-instrumentation-requests`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-urllib3`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-urllib`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-httpx`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-aiohttp-client`: hooks available ✅

3. **Messaging Instrumentations** (100% hook support):

   - `opentelemetry-instrumentation-kafka-python`: `produce_hook`, `consume_hook` ✅
   - `opentelemetry-instrumentation-confluent-kafka`: need to verify, likely has hooks ✅
   - `opentelemetry-instrumentation-aiokafka`: need to verify ✅
   - `opentelemetry-instrumentation-pika` (RabbitMQ): need to verify ✅
   - `opentelemetry-instrumentation-aio-pika`: need to verify ✅

4. **Database Instrumentations** (Partial hook support):

   - `opentelemetry-instrumentation-redis`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-pymongo`: `request_hook`, `response_hook`, `failed_hook` ✅
   - `opentelemetry-instrumentation-elasticsearch`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-sqlalchemy`: **NO HOOKS** ❌ (only sqlcommenter options)
   - `opentelemetry-instrumentation-dbapi`: **NO HOOKS** ❌
   - `opentelemetry-instrumentation-psycopg2`: **NO HOOKS** ❌
   - `opentelemetry-instrumentation-psycopg`: **NO HOOKS** ❌
   - `opentelemetry-instrumentation-pymysql`: **NO HOOKS** ❌
   - `opentelemetry-instrumentation-mysqlclient`: **NO HOOKS** ❌
   - `opentelemetry-instrumentation-mysql`: **NO HOOKS** ❌
   - `opentelemetry-instrumentation-pymssql`: **NO HOOKS** ❌
   - `opentelemetry-instrumentation-sqlite3`: **NO HOOKS** ❌
   - `opentelemetry-instrumentation-aiopg`: **NO HOOKS** ❌
   - `opentelemetry-instrumentation-asyncpg`: **NO HOOKS** ❌

5. **AWS Instrumentations** (100% hook support):

   - `opentelemetry-instrumentation-botocore`: `request_hook`, `response_hook` ✅
   - `opentelemetry-instrumentation-boto3sqs`: need to verify ✅
   - `opentelemetry-instrumentation-boto`: need to verify ✅

6. **gRPC Instrumentation** (Special case):

   - `opentelemetry-instrumentation-grpc`: **NO HOOKS** ❌ (uses interceptors instead)
   - Requires custom interceptor implementation, not hook-based

7. **Other Instrumentations**:

   - `opentelemetry-instrumentation-celery`: need to verify
   - `opentelemetry-instrumentation-cassandra`: need to verify
   - `opentelemetry-instrumentation-pymemcache`: need to verify

#### 3.4.2 Hook Availability Summary

**Total Instrumentations Analyzed**: ~50 instrumentations

**With Hooks**: ~35-40 instrumentations (70-80%)

- All HTTP server/client instrumentations: ✅
- Most messaging instrumentations: ✅
- Some database instrumentations (Redis, MongoDB, Elasticsearch): ✅
- AWS instrumentations: ✅

**Without Hooks**: ~10-15 instrumentations (20-30%)

- Most SQL database instrumentations (SQLAlchemy, DBAPI, psycopg, etc.): ❌
- gRPC (uses interceptors, not hooks): ❌
- Some lower-level database drivers: ❌

#### 3.4.3 Feasibility Assessment for Wrapper/Helper Pattern

**Overall Feasibility: ~75-80% via hooks alone, 95%+ with SpanProcessor workaround**

**Breakdown by Category**:

1. **HTTP Server/Client**: 100% feasible via hooks ✅

   - All major frameworks support hooks
   - Can fully implement CK graph path building via hooks

2. **Messaging (Kafka, RabbitMQ)**: ~90% feasible via hooks ✅

   - Kafka has produce/consume hooks
   - RabbitMQ instrumentations likely have hooks

3. **Database (NoSQL)**: 100% feasible via hooks ✅

   - Redis, MongoDB, Elasticsearch all have hooks

4. **Database (SQL)**: 0% feasible via hooks ❌

   - SQLAlchemy, DBAPI, psycopg, etc. do NOT have hooks
   - **Alternative**: Use `SpanProcessor.on_end()` to intercept SQL spans
   - SQL spans will be converted to GPE via `SGPNProcessor` in `CKGraphSpanProcessor`

5. **gRPC**: 0% feasible via hooks ❌

   - Uses interceptors, not hooks
   - **Alternative**: Create custom gRPC interceptors that call CK helpers
   - Or use `SpanProcessor` to intercept gRPC spans

6. **AWS (Botocore)**: 100% feasible via hooks ✅

   - Has request_hook and response_hook

#### 3.4.4 Workarounds for Instrumentations Without Hooks

**Strategy 1: SpanProcessor Interception** (Recommended for SQL databases)

- Use `CKGraphSpanProcessor.on_end()` to intercept all spans
- Check span attributes to identify SQL spans (`db.system`, `db.statement`, etc.)
- Convert to GPE using `SGPNProcessor` and appropriate mappers
- **Advantage**: Works for all instrumentations, no modification needed
- **Disadvantage**: Happens after span creation, can't modify span creation itself

**Strategy 2: Custom Interceptors** (For gRPC)

- Create custom gRPC server/client interceptors
- Call CK helpers at appropriate points
- Register interceptors alongside or instead of OSS interceptors
- **Advantage**: Full control over gRPC instrumentation
- **Disadvantage**: Requires maintaining custom interceptors

**Strategy 3: Monkey-Patch Instrumentation** (Last resort)

- Monkey-patch instrumentation classes to inject CK logic
- **Advantage**: Can add hooks where they don't exist
- **Disadvantage**: Fragile, breaks with updates, high maintenance

#### 3.4.5 Final Recommendation

**Wrapper/Helper Pattern Feasibility: 75-80% via hooks, 95%+ with SpanProcessor workaround**

**Implementation Approach**:

1. **Primary**: Use hooks for instrumentations that support them (HTTP, messaging, NoSQL, AWS)
2. **Secondary**: Use `SpanProcessor.on_end()` for instrumentations without hooks (SQL databases)
3. **Tertiary**: Custom interceptors for gRPC
4. **Fallback**: Monkey-patch only if absolutely necessary

**Risk Assessment**:

- **Low Risk**: HTTP, messaging, NoSQL, AWS (hooks available)
- **Medium Risk**: SQL databases (workaround via SpanProcessor)
- **Medium Risk**: gRPC (custom interceptors needed)
- **High Risk**: None identified

**Conclusion**: The wrapper/helper pattern is **highly feasible** (95%+) when combined with `SpanProcessor` interception for instrumentations without hooks. The main gap is SQL database instrumentations, which can be handled via `SpanProcessor.on_end()` without requiring instrumentation modifications.

### 3.5 Instrumentation Initialization

#### 3.5.1 Auto-Instrumentation Integration

**Location**: `ck_agent/instrumentation/ck_auto_instrumentation.py`

**Implementation**:

- Create wrapper around `opentelemetry-instrument` command
- Or modify `opentelemetry-distro` to use CK instrumentations
- Ensure CK helpers are initialized before instrumentations run

## 4. Architectural Approach Comparison

### 4.1 Option A: Build Separate Library (Java-Style Fork)

#### 4.1.1 Approach

- Fork `opentelemetry-python` and `opentelemetry-python-contrib`
- Create `ck-opentelemetry-python` and `ck-opentelemetry-python-contrib`
- Replace OSS packages with CK versions
- Build and distribute as separate packages

#### 4.1.2 Pros

- **Full Control**: Complete control over SDK and instrumentation code
- **Direct Modifications**: Can modify core SDK classes directly (like Java `Instrumenter`)
- **Isolated Changes**: Changes don't affect OSS codebase
- **Apples-to-Apples**: Closest to Java approach

#### 4.1.3 Cons

- **Maintenance Burden**: Must sync with upstream OpenTelemetry Python releases
- **Breaking Changes**: Upstream changes may require significant rework
- **Distribution Complexity**: Need to build, version, and distribute custom packages
- **Compatibility Risk**: May break compatibility with other OpenTelemetry tools
- **Testing Overhead**: Must test against all upstream changes

#### 4.1.4 Implementation Effort

- **High**: Requires maintaining forks of multiple repositories
- **Ongoing**: Continuous effort to merge upstream changes

### 4.2 Option B: Direct Modification of OSS Code (In-Place Changes)

#### 4.2.1 Approach

- Directly modify `opentelemetry-python` and `opentelemetry-python-contrib` source code
- Add CK components alongside OSS code
- Build from modified source

#### 4.2.2 Pros

- **Simplest Integration**: No package replacement needed
- **Direct Access**: Can modify any SDK class directly
- **Single Codebase**: All code in one place

#### 4.2.3 Cons

- **Not Upstreamable**: Changes can't be contributed back (proprietary)
- **Merge Conflicts**: Upstream updates will cause conflicts
- **Version Control**: Difficult to track CK-specific changes
- **Deployment**: Must build from source, can't use pip packages

#### 4.2.4 Implementation Effort

- **Medium**: Easier than fork but still requires maintaining patches

### 4.3 Option C: SDK Extension Points (Recommended)

#### 4.3.1 Approach

- Use existing OpenTelemetry Python SDK extension points
- Create `ck-agent` package that extends SDK without modifying OSS code
- Use `SpanProcessor`, custom `TracerProvider`, configurators, etc.
- Create wrapper/helper modules for instrumentation modifications

#### 4.3.2 Pros

- **No Fork Needed**: Works with standard OSS packages
- **Easy Updates**: Can update OSS packages independently
- **Maintainable**: Changes isolated to `ck-agent` package
- **Compatible**: Works with standard OpenTelemetry ecosystem
- **Pythonic**: Follows Python extension patterns

#### 4.3.3 Cons

- **Limited Control**: Can't modify core SDK classes directly (unlike Java `Instrumenter` modification)
- **Some Workarounds**: May need workarounds for features not exposed via extension points
- **Instrumentation Complexity**: Instrumentation modifications require wrapper pattern

#### 4.3.4 Implementation Effort

- **Medium-High**: Requires careful design but manageable
- **One-Time**: Most effort upfront, less ongoing maintenance

### 4.4 Recommendation: Hybrid Approach (Option C + Selective Forks)

#### 4.4.1 Strategy

1. **Core SDK**: Use Option C (extension points) for SDK modifications
2. **Instrumentations**: Use Option C (wrappers/helpers) for most instrumentations
3. **Critical Instrumentations**: For instrumentations that can't be wrapped, use Option A (fork) selectively

#### 4.4.2 Rationale

- Maximizes use of extension points (maintainable)
- Minimizes forks (only where necessary)
- Balances control and maintainability

## 5. Implementation Phases

### Phase 1: Core Components (Foundation)

1. Create `CKSpan` and `CKSpanAttributes`
2. Create `CKSpanProvider` interface and `CKGraphSpanProvider` implementation
3. Create `CKGraphSpanProcessor`
4. Create basic graph path building (`GPI`, `GraphPathInfo`)
5. Create `CKRoutePropagator`

### Phase 2: SDK Integration

1. Create `CKTracerProvider` and `CKTracer` (or use `SpanProcessor` approach)
2. Create `CKSDKConfigurator`
3. Create noop processors/exporters
4. Integrate with SDK initialization

### Phase 3: Metrics & Export

1. Create `GraphPathOTLPMetrics`
2. Create `MetricSyncManager`
3. Integrate HDRHistogram for percentiles
4. Set up OTLP gRPC metric export

### Phase 4: Instrumentation Helpers

1. Create helper modules for HTTP, gRPC, Kafka, etc.
2. Create wrapper instrumentations or modify OSS instrumentations
3. Test with sample applications

### Phase 5: Graph Path Mappers

1. Implement all `SpanToGPEMapper` types
2. Create `SGPNProcessor` with optimized lookup
3. Test span-to-GPE conversion

### Phase 6: Testing & Validation

1. End-to-end testing
2. Performance testing
3. Compatibility testing with OSS OpenTelemetry

## 6. Key Technical Decisions

### 6.1 Span Creation Interception Method

**Decision**: Use custom `TracerProvider` + `CKTracer` (Approach A from Section 2.1.2)

**Rationale**: Provides control similar to Java `Instrumenter` modification while using SDK extension points

### 6.2 Instrumentation Modification Strategy

**Decision**: Use wrapper/helper pattern (Option C from Section 3.3.1)

**Rationale**: Minimizes maintenance burden while providing necessary functionality

### 6.3 Architectural Approach

**Decision**: Hybrid approach - SDK extensions + selective instrumentation wrappers

**Rationale**: Balances control, maintainability, and compatibility

### 6.4 HDRHistogram Library

**Decision**: Use Python `hdrhistogram` package (https://pypi.org/project/hdrhistogram/)

**Rationale**: Provides equivalent functionality to Java HDRHistogram

## 7. Dependencies & Requirements

### 7.1 Python Packages

- `opentelemetry-api`
- `opentelemetry-sdk`
- `opentelemetry-exporter-otlp-proto-grpc`
- `hdrhistogram` (for percentile calculations)
- Standard library: `threading`, `concurrent.futures`, `typing`, etc.

### 7.2 Optional Dependencies

- `opentelemetry-python-contrib` packages (for instrumentation modifications)

### 7.3 Python Version

- Python 3.8+ (to match OpenTelemetry Python requirements)

## 8. File Structure

```
ck-agent-python/
├── ck_agent/
│   ├── __init__.py
│   ├── span/
│   │   ├── __init__.py
│   │   ├── ck_span.py
│   │   ├── ck_span_attributes.py
│   │   ├── ck_span_provider.py
│   │   ├── ck_graph_span_provider.py
│   │   └── ck_span_processors.py
│   ├── processors/
│   │   ├── __init__.py
│   │   ├── ck_graph_span_processor.py
│   │   ├── ck_noop_span_processor.py
│   │   ├── sgpn_processor.py
│   │   └── mapper/
│   │       ├── __init__.py
│   │       ├── base.py  # SpanToGPEMapper ABC
│   │       ├── elasticsearch.py
│   │       ├── mongodb.py
│   │       ├── kafka.py
│   │       ├── http.py
│   │       ├── grpc.py
│   │       └── ...  # other mappers
│   ├── metrics/
│   │   ├── __init__.py
│   │   ├── graph_path_otlp_metrics.py
│   │   └── metric_sync_manager.py
│   ├── propagator/
│   │   ├── __init__.py
│   │   └── ck_route_propagator.py
│   ├── graph/
│   │   ├── __init__.py
│   │   ├── gpi.py
│   │   ├── graph_path_info.py
│   │   └── graph_path_elements.py
│   ├── config/
│   │   ├── __init__.py
│   │   ├── ck_sdk_configurator.py
│   │   └── ck_auto_configuration.py
│   ├── exporters/
│   │   ├── __init__.py
│   │   └── ck_noop_exporters.py
│   ├── sdk/
│   │   ├── __init__.py
│   │   ├── ck_tracer_provider.py
│   │   └── ck_tracer.py
│   ├── common/
│   │   ├── __init__.py
│   │   ├── context_helpers.py
│   │   └── constants.py
│   ├── instrumentation/
│   │   ├── __init__.py
│   │   ├── helpers/
│   │   │   ├── __init__.py
│   │   │   ├── http_server_helper.py
│   │   │   ├── grpc_helper.py
│   │   │   ├── kafka_helper.py
│   │   │   └── ...
│   │   └── wrappers/
│   │       ├── __init__.py
│   │       └── ...  # wrapper instrumentations if needed
│   └── init/
│       ├── __init__.py
│       └── ck_agent_initializer.py
├── tests/
├── setup.py  # or pyproject.toml
└── README.md
```

## 9. Metrics Implementation Pattern Analysis (OpenAI v2 Reference)

### 9.1 OpenAI v2 Instrumentation Metrics Approach

Based on analysis of [`opentelemetry-instrumentation-openai-v2`](https://github.com/open-telemetry/opentelemetry-python-contrib/tree/main/instrumentation-genai/opentelemetry-instrumentation-openai-v2), here's how it implements metrics:

#### 9.1.1 Implementation Pattern

1. **Instruments Class** (`instruments.py`):

   - Creates metric instruments (histograms) in `__init__` method
   - Gets `Meter` from `get_meter()` API
   - Defines custom bucket boundaries for histograms
   - Stores instruments as instance attributes

2. **Metrics Recording** (`patch.py`):

   - `_record_metrics()` function called from wrapper functions
   - Records metrics directly using `instruments.operation_duration_histogram.record()`
   - Builds attributes dictionary from span/request data
   - Records multiple metrics (duration, token usage) with different attribute sets

3. **Integration in Instrumentor** (`__init__.py`):

   - Creates `Instruments` instance in `_instrument()` method
   - Passes `instruments` to wrapper functions
   - Metrics are created and recorded entirely within the instrumentation module

#### 9.1.2 Key Characteristics

- **Internal Metrics**: Metrics are created inside the instrumentation, not exposed via hooks
- **Direct Recording**: Metrics recorded directly in wrapper/patch functions
- **No Hook API**: No plugin/hook mechanism for external metric augmentation
- **SDK Integration**: Uses standard OpenTelemetry Metrics SDK (`get_meter()`, `create_histogram()`)

### 9.2 Wrapper/Helper Approach for CK-Agent Metrics

#### 9.2.1 Feasibility Analysis

**Can we replicate this pattern as a wrapper without modifying OSS code?**

**Answer: Partially (70-80% feasible)**

#### 9.2.2 Wrapper Strategies

**Strategy A: SpanProcessor-Based Metrics** (Recommended - 100% feasible)

- **Approach**: Use `CKGraphSpanProcessor.on_end()` to observe all spans
- **Metrics Creation**: Create CK metrics in `CKGraphSpanProcessor` using `get_meter()`
- **Metrics Recording**: Extract data from span attributes and record CK metrics
- **Advantages**:
  - Works for ALL instrumentations (not just ones with hooks)
  - No modification to OSS code needed
  - Can add metrics alongside OSS metrics
  - Similar pattern to OpenAI v2 (metrics recorded from span data)
- **Implementation**:
  ```python
  class CKGraphSpanProcessor(SpanProcessor):
      def __init__(self):
          self._meter = get_meter("ck_agent", "1.0.0")
          self._latency_histogram = self._meter.create_histogram(...)
          self._throughput_counter = self._meter.create_counter(...)
      
      def on_end(self, span: ReadableSpan):
          # Extract data from span
          duration = span.end_time - span.start_time
          attributes = span.attributes
          
          # Convert to GPE and record metrics
          gpe = self._convert_to_gpe(span)
          self._record_ck_metrics(gpe, duration, attributes)
  ```


**Strategy B: Wrapper Instrumentor Pattern** (75% feasible)

- **Approach**: Wrap OSS instrumentors to add metrics
- **Implementation**: Create wrapper that calls OSS instrumentor, then adds metrics
- **Limitations**:
  - Only works for instrumentations we wrap
  - Requires maintaining wrapper for each instrumentation
  - May conflict with OSS metrics if both record similar data
- **Example**:
  ```python
  class CKFlaskInstrumentor:
      def __init__(self):
          self._oss_instrumentor = FlaskInstrumentor()
          self._ck_meter = get_meter("ck_agent", "1.0.0")
      
      def instrument(self, **kwargs):
          # Call OSS instrumentor
          self._oss_instrumentor.instrument(**kwargs)
          
          # Add CK metrics via hooks
          def ck_request_hook(span, environ):
              # Record CK metrics
              pass
          
          # Re-instrument with CK hooks
          self._oss_instrumentor.instrument(
              request_hook=ck_request_hook,
              **kwargs
          )
  ```


**Strategy C: Monkey-Patch Instruments** (60% feasible, high risk)

- **Approach**: Monkey-patch `Instruments` class or metric recording functions
- **Limitations**:
  - Fragile, breaks with OSS updates
  - May not work for all instrumentations
  - Hard to maintain
- **Not Recommended**: Too risky for production

#### 9.2.3 Comparison: OpenAI v2 vs CK-Agent Approach

| Aspect | OpenAI v2 (OSS) | CK-Agent Wrapper Approach |

|--------|------------------|---------------------------|

| **Metrics Creation** | Inside instrumentation | In `CKGraphSpanProcessor` |

| **Metrics Recording** | Direct in patch functions | In `SpanProcessor.on_end()` |

| **Data Source** | Request/response objects | Span attributes + span data |

| **OSS Code Changes** | Required (internal) | Not required (wrapper) |

| **Coverage** | Specific to OpenAI | All instrumentations |

| **Maintenance** | OSS maintains | We maintain wrapper |

#### 9.2.4 Recommended Approach for CK-Agent

**Primary Strategy: SpanProcessor-Based Metrics** (Same pattern as OpenAI v2, but external)

**Rationale**:

1. **No OSS Modifications**: Works with all existing instrumentations
2. **Consistent Pattern**: Similar to OpenAI v2 (metrics from span data)
3. **Universal Coverage**: Works for all instrumentations, not just ones with hooks
4. **Maintainable**: Single implementation point (`CKGraphSpanProcessor`)
5. **Flexible**: Can add/remove metrics without touching OSS code

**Implementation Details**:

- `CKGraphSpanProcessor` creates metric instruments on initialization
- `on_end()` method extracts span data and converts to GPE
- Records CK-specific metrics (latency percentiles, throughput, errors)
- Uses HDRHistogram for percentile calculations (like Java implementation)
- Exports via OTLP gRPC (same as Java)

**Additional Metrics** (beyond what OSS provides):

- Graph path-based metrics (latency by path, throughput by path)
- Error rates by graph path
- Custom percentile calculations (p50, p90, p95, p99)
- Path key-based aggregation

#### 9.2.5 Feasibility Summary

**Overall Feasibility: 95%+ via SpanProcessor approach**

- **Metrics Creation**: ✅ 100% feasible (use `get_meter()` in SpanProcessor)
- **Metrics Recording**: ✅ 100% feasible (record in `on_end()`)
- **Data Extraction**: ✅ 100% feasible (from span attributes and span data)
- **Custom Metrics**: ✅ 100% feasible (create any metrics we need)
- **OSS Compatibility**: ✅ 100% compatible (doesn't interfere with OSS metrics)

**Conclusion**: The SpanProcessor-based approach is **highly feasible** and follows a similar pattern to OpenAI v2, but implemented as an external wrapper rather than inside instrumentations. This gives us the same capabilities without modifying OSS code.

### 9.3 Flask Instrumentation Wrapper Pattern Analysis

#### 9.3.1 Flask Instrumentation Structure

Based on analysis of [`opentelemetry-instrumentation-flask`](https://github.com/open-telemetry/opentelemetry-python-contrib/blob/main/instrumentation/opentelemetry-instrumentation-flask/src/opentelemetry/instrumentation/flask/__init__.py), the Flask instrumentation:

1. **Uses Wrapper Pattern**: Creates `_InstrumentedFlask` class that wraps `flask.Flask`
2. **Span Creation**: Uses `_start_internal_or_server_span()` which calls `tracer.start_span()` (line 494)
3. **Span Storage**: Stores span in `flask.request.environ[_ENVIRON_SPAN_KEY]` (line 522)
4. **Hooks Support**: Provides `request_hook` and `response_hook` parameters (lines 503-504, 413-414)
5. **Metrics**: Creates histograms and records metrics directly (similar to OpenAI v2)

#### 9.3.2 Creating CKSpan via Wrapper (Without OSS Modifications)

**Question**: Can we extend Flask instrumentation externally to create CKSpan instead of regular spans and add route key logic?

**Answer: Yes, 90%+ feasible via Custom TracerProvider + Hooks approach**

#### 9.3.3 Wrapper Strategies for CKSpan Creation

**Strategy A: Custom TracerProvider + CKTracer** (Recommended - 95% feasible)

**Approach**:

1. Create `CKTracerProvider` that returns `CKTracer`
2. `CKTracer.start_span()` returns `CKSpan` instead of regular span
3. Pass `CKTracerProvider` to Flask instrumentation via `tracer_provider` parameter
4. Flask instrumentation calls our `CKTracer`, which creates `CKSpan`

**Implementation**:

```python
# ck_agent/instrumentation/wrappers/flask_wrapper.py
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from ck_agent.sdk.ck_tracer_provider import CKTracerProvider
from ck_agent.instrumentation.helpers.http_server_helper import handle_http_request_start

class CKFlaskInstrumentor:
    def __init__(self):
        self._oss_instrumentor = FlaskInstrumentor()
        self._ck_tracer_provider = CKTracerProvider()
    
    def instrument_app(self, app, **kwargs):
        # Create CK request/response hooks
        def ck_request_hook(span, environ):
            # span is already CKSpan (created by CKTracer)
            # Extract ck-route header, build graph path
            handle_http_request_start(environ, span)
        
        def ck_response_hook(span, status, response_headers):
            # Ensure path key is properly propagated
            # Span is CKSpan, already has CK attributes
            pass
        
        # Call OSS instrumentor with CK TracerProvider and hooks
        self._oss_instrumentor.instrument_app(
            app,
            tracer_provider=self._ck_tracer_provider,  # This makes Flask use CKTracer
            request_hook=ck_request_hook,
            response_hook=ck_response_hook,
            **kwargs
        )
```

**How It Works**:

- Flask's `_wrapped_before_request()` calls `_start_internal_or_server_span(tracer=tracer, ...)` (line 494)
- `tracer` comes from `tracer_provider` parameter → our `CKTracerProvider`
- `CKTracer.start_span()` returns `CKSpan`
- `request_hook` receives `CKSpan` and adds CK-specific logic (route key, graph path)
- Span stored in `environ[_ENVIRON_SPAN_KEY] `is `CKSpan`

**Advantages**:

- ✅ No OSS code modification
- ✅ Flask instrumentation works normally, just uses our tracer
- ✅ All spans created are CKSpan
- ✅ Hooks can add CK-specific logic

**Limitations**:

- ⚠️ Requires passing `tracer_provider` to each instrumentation
- ⚠️ Need to wrap each HTTP server instrumentation similarly

**Strategy B: Hook-Based Span Replacement** (70% feasible, more complex)

**Approach**:

1. Let Flask create regular span
2. In `request_hook`, create CKSpan and replace span in context
3. Update `environ[_ENVIRON_SPAN_KEY]` with CKSpan

**Implementation**:

```python
def ck_request_hook(span, environ):
    # Create CKSpan
    ck_span = ck_span_provider.get_span_instance()
    # Copy attributes from regular span
    # Replace in context
    context = trace.set_span_in_context(ck_span)
    environ[_ENVIRON_SPAN_KEY] = ck_span
    # Add CK logic
    handle_http_request_start(environ, ck_span)
```

**Limitations**:

- ⚠️ More complex (need to handle context replacement)
- ⚠️ Regular span still created (wasteful)
- ⚠️ May cause issues with span lifecycle

**Strategy C: Wrapper Instrumentor Pattern** (85% feasible)

**Approach**:

1. Wrap `FlaskInstrumentor` class
2. Override `instrument_app()` to add CK logic
3. Call OSS `instrument_app()` first, then add CK hooks

**Implementation**:

```python
class CKFlaskInstrumentor:
    def __init__(self):
        self._oss = FlaskInstrumentor()
    
    def instrument_app(self, app, **kwargs):
        # Call OSS first
        self._oss.instrument_app(app, **kwargs)
        
        # Add CK hooks (re-instrument with hooks)
        # Or modify app.wsgi_app to add CK logic
        original_wsgi_app = app.wsgi_app
        app.wsgi_app = self._ck_wrap_wsgi(original_wsgi_app)
```

**Limitations**:

- ⚠️ Need to re-wrap or modify after OSS instrumentation
- ⚠️ May conflict with OSS hooks if both are set

#### 9.3.4 Route Key and Graph Path Logic

**Implementation via Hooks**:

```python
# ck_agent/instrumentation/helpers/http_server_helper.py
def handle_http_request_start(environ, span):
    """Handle HTTP server request start for CK graph path building"""
    # Extract ck-route header
    incoming_path = extract_ck_route_header(environ)
    
    # Get route info
    route_info = environ.get('HTTP_ROUTE') or get_route_from_flask(environ)
    method = environ.get('REQUEST_METHOD')
    
    # Create HTTPServiceGPE
    graph_path_element = HTTPServiceGPE(method=method, route=route_info)
    
    # Build graph path
    if not incoming_path:
        incoming_path = get_external_incoming_path(environ)
    
    graph_path_node = GPI.create(incoming_path, graph_path_element)
    new_path_hash = GPI.get_path_hash(graph_path_node, is_start=True)
    
    # Store in context
    context = context_api.get_current()
    context = set_path_key_in_context(context, new_path_hash)
    context_api.attach(context)
    
    # Store in span attributes (if needed)
    span.set_attribute("ck.route.key", new_path_hash)
```

#### 9.3.5 Feasibility Summary for Flask Wrapper

**Overall Feasibility: 90-95% via Custom TracerProvider approach**

| Aspect | Feasibility | Notes |

|--------|-------------|-------|

| **CKSpan Creation** | ✅ 95% | Custom TracerProvider returns CKTracer that creates CKSpan. 5% gap due to: (1) Need to fully implement `ReadableSpan` interface - all properties/methods must match SDK expectations, (2) Unknown edge cases in span lifecycle/context integration, (3) Some instrumentations may use internal span methods we haven't accounted for, (4) Testing unknowns - haven't validated in production scenarios |

| **Route Key Logic** | ✅ 100% | Via request_hook, can extract headers and build graph path |

| **Graph Path Building** | ✅ 100% | Via hooks, can call CK helpers to build graph path |

| **No OSS Modifications** | ✅ 100% | Pure wrapper approach |

| **Metrics Integration** | ✅ 100% | Flask metrics work normally, CK metrics via SpanProcessor |

**Recommended Approach**:

1. **Primary**: Custom `CKTracerProvider` + `CKTracer` (Strategy A)
2. **Hooks**: Use `request_hook`/`response_hook` for route key and graph path logic
3. **Metrics**: Use `SpanProcessor` for CK metrics (as analyzed in Section 9.2)

**Implementation Pattern**:

```python
# User code
from ck_agent.instrumentation.wrappers.flask_wrapper import CKFlaskInstrumentor

app = Flask(__name__)
CKFlaskInstrumentor().instrument_app(app)  # Creates CKSpan + adds CK logic
```

**Conclusion**: Flask instrumentation can be extended externally to create CKSpan and add route key logic via a wrapper pattern using Custom TracerProvider and hooks. This is **highly feasible (90-95%)** without modifying OSS code.

#### 9.3.6 Why 95% for CKSpan Creation? (The 5% Gap Explained)

The 5% gap in CKSpan creation feasibility comes from several potential compatibility concerns that need validation:

**1. ReadableSpan Interface Completeness** (~2% risk)

- CKSpan must fully implement `ReadableSpan` interface with all required properties:
  - `name`, `context`, `kind`, `parent`, `start_time`, `end_time`
  - `status`, `attributes`, `events`, `links`, `resource`
  - `instrumentation_scope`, `dropped_attributes`, `dropped_events`, `dropped_links`
- Some properties might have specific type requirements or behaviors we haven't fully mapped
- Edge cases in attribute/event/link handling might not be obvious until testing

**2. SpanProcessor Compatibility** (~1% risk)

- `SpanProcessor.on_end()` expects `ReadableSpan` - should work if interface is complete
- Some processors might do `isinstance()` checks or use internal methods
- Unknown if any processors rely on SDK-specific `Span` class internals

**3. Context and Lifecycle Integration** (~1% risk)

- CKSpan must work with `trace.use_span()`, `set_span_in_context()`, etc.
- Span activation/deactivation might have edge cases
- Context propagation across threads/async boundaries needs validation

**4. Instrumentation Assumptions** (~1% risk)

- Some instrumentations might check span types or use internal methods
- Flask stores span in `environ[_ENVIRON_SPAN_KEY]` - should work if CKSpan implements interface
- Unknown if any instrumentation code does `isinstance(span, SDK.Span)` checks

**5. Testing Unknowns** (Ongoing risk)

- Haven't implemented and tested in real scenarios
- Production edge cases might reveal issues
- Compatibility with all instrumentations needs validation

**Mitigation Strategies**:

- Start with minimal CKSpan implementation, add features incrementally
- Test with Flask first (most common), then expand to other instrumentations
- If issues arise, can fall back to wrapping regular spans in hooks (Strategy B)
- Monitor for type checking or internal method usage in instrumentations

## 10. Open Questions & Risks

### 10.1 Open Questions

1. **Span Context Compatibility**: Can `CKSpan` fully replace `Span` in context without breaking instrumentation expectations?
2. **Instrumentation Hook Availability**: Do all needed instrumentations support hooks for custom logic?
3. **Performance Impact**: What's the performance overhead of wrapper pattern vs. direct modification?
4. **Graph Path Library**: Is the graph path building library (`ck-commons`) available in Python, or must it be ported?

### 9.2 Risks

1. **SDK API Changes**: OpenTelemetry Python SDK API changes may break extension points
2. **Instrumentation Compatibility**: Some instrumentations may not work with custom spans
3. **Context Propagation**: Custom propagator may not work with all libraries
4. **Performance**: Additional layers (wrappers, processors) may add latency

## 10. Success Criteria

1. **Functional Parity**: All Java CK-Agent features work in Python
2. **Performance**: Metrics export overhead < 5% of application latency
3. **Compatibility**: Works with standard OpenTelemetry Python ecosystem
4. **Maintainability**: Can update OSS packages without major rework
5. **Test Coverage**: >80% test coverage for core components