# OpenTelemetry Python Architecture Documentation

## Overview

OpenTelemetry Python is the official OpenTelemetry implementation for Python applications. Unlike Java's agent-based approach, Python uses library-based instrumentation where applications explicitly configure the SDK. The architecture follows a clean separation between API (interfaces) and SDK (implementation), allowing libraries to depend only on the API while applications choose their SDK implementation.

## Key Design Principles

1. **API/SDK Separation**: Libraries depend only on the API, applications choose the SDK
2. **Explicit Configuration**: Applications must explicitly set up the SDK (no automatic agent)
3. **Library Instrumentation**: Uses decorators, wrappers, and monkey-patching (not bytecode manipulation)
4. **Context Manager Pattern**: Heavy use of Python's `with` statements for span lifecycle
5. **Pluggable Components**: Exporters, processors, samplers are all pluggable

## Architecture Components

### 1. API Package (`opentelemetry-api`)

**Location**: `opentelemetry-api/src/opentelemetry/`

The API package provides abstract interfaces and no-op implementations:

- **Abstract Classes**: `TracerProvider`, `Tracer`, `Span`, `SpanExporter`
- **No-Op Implementations**: Allow libraries to use the API without requiring an SDK
- **Context Management**: Abstract context propagation mechanisms
- **No Dependencies**: Pure interfaces, no implementation details

**Key Interfaces**:

```python
# opentelemetry/trace/__init__.py
class TracerProvider(ABC):
    @abstractmethod
    def get_tracer(self, name: str, version: str = None) -> Tracer:
        pass

class Tracer(ABC):
    @abstractmethod
    def start_span(self, name: str, ...) -> Span:
        pass

class Span(ABC):
    @abstractmethod
    def set_attribute(self, key: str, value: Any) -> None:
        pass
    
    @abstractmethod
    def end(self, end_time: int = None) -> None:
        pass
```

### 2. SDK Package (`opentelemetry-sdk`)

**Location**: `opentelemetry-sdk/src/opentelemetry/sdk/`

The SDK provides the reference implementation of the API:

#### **TracerProvider**

**Location**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/__init__.py`

- Manages tracers, span processors, samplers, resource, and ID generators
- Entry point for creating tracers
- Global instance set via `trace.set_tracer_provider()`

```python
class TracerProvider(trace_api.TracerProvider):
    def __init__(
        self,
        sampler: sampling.Sampler = None,
        resource: Resource = None,
        id_generator: IdGenerator = None,
        span_limits: SpanLimits = None,
    ):
        # Initializes with samplers, resource, etc.
    
    def get_tracer(self, name: str, version: str = None) -> Tracer:
        # Returns a Tracer instance
```

#### **Tracer**

**Location**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/__init__.py`

- Creates and manages spans
- Handles span context and parent relationships
- Implements sampling logic

```python
class Tracer(trace_api.Tracer):
    def start_span(
        self,
        name: str,
        context: Optional[Context] = None,
        kind: SpanKind = SpanKind.INTERNAL,
        attributes: Attributes = None,
        links: Sequence[Link] = None,
        start_time: Optional[int] = None,
    ) -> trace_api.Span:
        # 1. Get parent span context from context
        # 2. Generate trace_id (new or from parent)
        # 3. Call sampler to decide if span should be recorded
        # 4. Create SpanContext (trace_id, span_id, flags)
        # 5. Create Span object (if sampled) or NonRecordingSpan
        # 6. Call span_processor.on_start()
        # 7. Return span
```

#### **Span**

**Location**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/__init__.py`

- Represents a single operation in a trace
- Stores: name, attributes, events, links, timestamps, status
- Implements the full span lifecycle

```python
class Span(trace_api.Span, ReadableSpan):
    def __init__(
        self,
        name: str,
        context: SpanContext,
        parent: Optional[SpanContext] = None,
        sampler: Sampler = None,
        resource: Resource = None,
        attributes: Attributes = None,
        events: Sequence[Event] = None,
        links: Sequence[Link] = (),
        kind: SpanKind = SpanKind.INTERNAL,
        span_processor: SpanProcessor = None,
        limits: SpanLimits = None,
    ):
        # Initializes with bounded attributes, events, links
    
    def start(self, start_time: int = None, parent_context: Context = None):
        # Sets start time, calls span_processor.on_start()
    
    def end(self, end_time: int = None):
        # Sets end time, calls span_processor.on_end()
```

### 3. Span Processors

**Location**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/export/__init__.py`

Span processors are hooks that get called when spans start and end.

#### **SpanProcessor Interface**

```python
class SpanProcessor:
    def on_start(self, span: Span, parent_context: Context = None) -> None:
        """Called when a span starts (synchronously)"""
    
    def on_end(self, span: ReadableSpan) -> None:
        """Called when a span ends (synchronously)"""
    
    def shutdown(self) -> None:
        """Called when TracerProvider shuts down"""
    
    def force_flush(self, timeout_millis: int = 30000) -> bool:
        """Flush pending spans"""
```

#### **SimpleSpanProcessor**

- Exports each span immediately when it ends
- Synchronous export (blocks until complete)
- Good for debugging/development

```python
class SimpleSpanProcessor(SpanProcessor):
    def __init__(self, span_exporter: SpanExporter):
        self.span_exporter = span_exporter
    
    def on_end(self, span: ReadableSpan) -> None:
        if span.context.trace_flags.sampled:
            self.span_exporter.export((span,))
```

#### **BatchSpanProcessor**

- Batches spans before exporting
- Asynchronous background worker thread
- Configurable via environment variables:
  - `OTEL_BSP_SCHEDULE_DELAY`: Delay between exports (default: 5000ms)
  - `OTEL_BSP_MAX_QUEUE_SIZE`: Max queue size (default: 2048)
  - `OTEL_BSP_MAX_EXPORT_BATCH_SIZE`: Max batch size (default: 512)
  - `OTEL_BSP_EXPORT_TIMEOUT`: Export timeout (default: 30000ms)

```python
class BatchSpanProcessor(SpanProcessor):
    def __init__(
        self,
        span_exporter: SpanExporter,
        max_queue_size: int = None,
        schedule_delay_millis: float = None,
        max_export_batch_size: int = None,
        export_timeout_millis: float = None,
    ):
        self._batch_processor = BatchProcessor(
            span_exporter,
            schedule_delay_millis,
            max_export_batch_size,
            max_queue_size,
            "Span",
        )
    
    def on_end(self, span: ReadableSpan) -> None:
        if span.context.trace_flags.sampled:
            self._batch_processor.emit(span)  # Adds to queue
```

**BatchProcessor** (shared implementation):
- Maintains a queue of spans
- Background worker thread periodically exports batches
- Handles queue overflow (drops spans when full)
- Thread-safe operations

### 4. Exporters

**Location**: `exporter/opentelemetry-exporter-*/`

Exporters send telemetry data to backends.

#### **SpanExporter Interface**

```python
class SpanExporter:
    def export(self, spans: Sequence[ReadableSpan]) -> SpanExportResult:
        """Exports a batch of spans"""
    
    def shutdown(self) -> None:
        """Shuts down the exporter"""
    
    def force_flush(self, timeout_millis: int = 30000) -> bool:
        """Flush pending exports"""
```

#### **Available Exporters**

1. **OTLP Exporter** (`opentelemetry-exporter-otlp-proto-grpc` / `-http`):
   - Exports to OpenTelemetry Collector or backends
   - Supports gRPC and HTTP protocols
   - Most common production exporter

2. **Zipkin Exporter** (`opentelemetry-exporter-zipkin-json` / `-proto-http`):
   - Exports to Zipkin backend
   - Supports JSON and Protobuf formats

3. **Console Exporter** (built into SDK):
   - Prints spans to console
   - Useful for debugging

4. **Prometheus Exporter** (`opentelemetry-exporter-prometheus`):
   - For metrics (not spans)
   - Exposes metrics via HTTP endpoint

### 5. Sampling

**Location**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/sampling.py`

Sampling decides whether to record and export spans.

#### **Sampler Interface**

```python
class Sampler(ABC):
    @abstractmethod
    def should_sample(
        self,
        context: Context,
        trace_id: int,
        name: str,
        kind: SpanKind,
        attributes: Attributes,
        links: Sequence[Link],
    ) -> SamplingResult:
        pass
```

#### **Sampler Types**

1. **AlwaysOnSampler**: Records and exports all spans
2. **AlwaysOffSampler**: Records nothing
3. **TraceIdRatioBasedSampler**: Samples based on trace_id hash
4. **ParentBasedSampler**: Respects parent span's sampling decision

**Sampling Decision**:
- Made at span creation time
- If not sampled → returns `NonRecordingSpan` (no-op)
- If sampled → creates real `Span` object
- Sampling result stored in `TraceFlags`

### 6. Context Propagation

**Location**: `opentelemetry-api/src/opentelemetry/context/`

- Uses `opentelemetry.context` for context management
- Context carries: active span, baggage, custom values
- Thread-local storage with contextvars (Python 3.7+)

#### **Context API**

```python
from opentelemetry import context

# Get current context
ctx = context.get_current()

# Set value in context
ctx = context.set_value("key", "value")

# Attach context (makes it current)
token = context.attach(ctx)

# Detach context
context.detach(token)
```

#### **Propagators**

**Location**: `propagator/opentelemetry-propagator-*/`

Propagators inject/extract context from carriers (HTTP headers, etc.):

1. **W3C TraceContext**: Standard W3C trace context propagation
2. **B3**: Zipkin's B3 propagation format
3. **Baggage**: Cross-cutting concerns propagation

```python
from opentelemetry.propagate import inject, extract

# Inject context into HTTP headers
headers = {}
inject(headers)

# Extract context from HTTP headers
context = extract(headers)
```

### 7. Resource

**Location**: `opentelemetry-sdk/src/opentelemetry/sdk/resources/`

- Describes the entity producing telemetry
- Contains attributes: `service.name`, `service.version`, `host.name`, etc.
- Attached to all spans from a TracerProvider
- Can be configured via `OTEL_RESOURCE_ATTRIBUTES` environment variable

### 8. Configuration

**Location**: `opentelemetry-sdk/src/opentelemetry/sdk/_configuration/__init__.py`

OpenTelemetry Python supports configuration via:

1. **Environment Variables**: Standard OTEL environment variables
2. **Programmatic API**: Direct SDK configuration
3. **Auto-instrumentation**: Automatic configuration via `opentelemetry-instrument`

#### **Environment Variables**

- `OTEL_SERVICE_NAME`: Service name for resource
- `OTEL_RESOURCE_ATTRIBUTES`: Additional resource attributes
- `OTEL_TRACES_EXPORTER`: Exporter to use (e.g., "otlp", "zipkin")
- `OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP exporter endpoint
- `OTEL_TRACES_SAMPLER`: Sampler to use (e.g., "always_on", "traceidratio")
- `OTEL_TRACES_SAMPLER_ARG`: Sampler argument (e.g., ratio for traceidratio)

#### **Programmatic Configuration**

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# 1. Create TracerProvider
provider = TracerProvider()

# 2. Create Exporter
exporter = OTLPSpanExporter(endpoint="http://localhost:4317")

# 3. Create SpanProcessor
processor = BatchSpanProcessor(exporter)

# 4. Add processor to provider
provider.add_span_processor(processor)

# 5. Set as global provider
trace.set_tracer_provider(provider)

# 6. Get tracer and create spans
tracer = trace.get_tracer(__name__)
```

### 9. Span Lifecycle

```
1. Application calls tracer.start_as_current_span("operation")
   ↓
2. Tracer.start_span() called
   ↓
3. Get parent span context from current context
   ↓
4. Generate trace_id (new if root, inherit if child)
   ↓
5. Generate span_id
   ↓
6. Sampler.should_sample() called
   ↓
7. Create SpanContext (trace_id, span_id, trace_flags)
   ↓
8. If sampled:
   - Create Span object
   - SpanProcessor.on_start() called
   - Span.start() sets start time
   ↓
9. Span stored in Context (becomes current span)
   ↓
10. Application code executes
   ↓
11. Context manager exits → Span.end() called
   ↓
12. SpanProcessor.on_end() called
   ↓
13. Span added to processor queue (BatchSpanProcessor)
   or exported immediately (SimpleSpanProcessor)
   ↓
14. Background worker (BatchSpanProcessor) exports batch
   ↓
15. SpanExporter.export() sends to backend
```

### 10. Data Flow

#### **Span Creation Flow**

```
Application Code
   ↓
tracer.start_as_current_span("operation")
   ↓
Tracer.start_span()
   ↓
Sampler.should_sample()
   ↓
Span created (if sampled)
   ↓
SpanProcessor.on_start()
   ↓
Span.start() - sets start time
   ↓
Span stored in Context
   ↓
Application executes
```

#### **Span Export Flow**

```
Span.end() called
   ↓
SpanProcessor.on_end()
   ↓
BatchSpanProcessor.emit(span)
   ↓
BatchProcessor._queue.appendleft(span)
   ↓
Background worker thread wakes up
   ↓
BatchProcessor._export()
   ↓
Batch of spans popped from queue
   ↓
SpanExporter.export(spans)
   ↓
OTLP/Zipkin/etc. endpoint
```

### 11. Key Differences from Java Agent

1. **No Agent**: Python uses library instrumentation, not bytecode manipulation
2. **Explicit Setup**: Applications must configure SDK explicitly (no automatic setup)
3. **Context Manager Pattern**: Heavy use of `with` statements for span lifecycle
4. **Threading Model**: Python's GIL affects concurrent processing
5. **Package Structure**: Separate packages for API, SDK, exporters, propagators
6. **Instrumentation**: Uses decorators, wrappers, monkey-patching (not ByteBuddy)
7. **No Bootstrap Classloader**: All code runs in application classloader equivalent

### 12. Instrumentation

**Note**: Instrumentation libraries are in a separate repository (`opentelemetry-python-contrib`)

Instrumentation approaches:
1. **Decorators**: Wrap functions/methods
2. **Monkey Patching**: Patch library code at import time
3. **Wrappers**: Wrap objects (e.g., HTTP clients)
4. **Middleware**: Framework-specific middleware (Flask, Django, etc.)

Example (conceptual):
```python
# Instrumentation decorator
def instrument_http_client():
    original_request = requests.Session.request
    
    def traced_request(self, method, url, **kwargs):
        tracer = trace.get_tracer(__name__)
        with tracer.start_as_current_span(f"HTTP {method}"):
            span.set_attribute("http.method", method)
            span.set_attribute("http.url", url)
            response = original_request(self, method, url, **kwargs)
            span.set_attribute("http.status_code", response.status_code)
            return response
    
    requests.Session.request = traced_request
```

### 13. Typical Usage Patterns

#### **Basic Setup**

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter

# Setup
provider = TracerProvider()
processor = BatchSpanProcessor(ConsoleSpanExporter())
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)

# Usage
tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("parent"):
    with tracer.start_as_current_span("child"):
        print("Hello from OpenTelemetry!")
```

#### **Production Setup with OTLP**

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

resource = Resource.create({
    "service.name": "my-service",
    "service.version": "1.0.0",
})

provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(endpoint="http://collector:4317")
processor = BatchSpanProcessor(exporter)
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
```

#### **Manual Instrumentation**

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

def my_function():
    with tracer.start_as_current_span("my_function") as span:
        span.set_attribute("custom.attribute", "value")
        span.add_event("event.name", {"key": "value"})
        # do work
        if error:
            span.record_exception(error)
            span.set_status(Status(StatusCode.ERROR, "error message"))
```

### 14. Key Files Reference

#### **API Package**

- **TracerProvider**: `opentelemetry-api/src/opentelemetry/trace/__init__.py`
- **Tracer**: `opentelemetry-api/src/opentelemetry/trace/__init__.py`
- **Span**: `opentelemetry-api/src/opentelemetry/trace/__init__.py`
- **Context**: `opentelemetry-api/src/opentelemetry/context/__init__.py`

#### **SDK Package**

- **TracerProvider**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/__init__.py`
- **Tracer**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/__init__.py`
- **Span**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/__init__.py`
- **SpanProcessor**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/__init__.py`
- **BatchSpanProcessor**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/export/__init__.py`
- **SimpleSpanProcessor**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/export/__init__.py`
- **Sampling**: `opentelemetry-sdk/src/opentelemetry/sdk/trace/sampling.py`
- **Configuration**: `opentelemetry-sdk/src/opentelemetry/sdk/_configuration/__init__.py`

#### **Exporters**

- **OTLP gRPC**: `exporter/opentelemetry-exporter-otlp-proto-grpc/`
- **OTLP HTTP**: `exporter/opentelemetry-exporter-otlp-proto-http/`
- **Zipkin**: `exporter/opentelemetry-exporter-zipkin-json/`

#### **Propagators**

- **W3C TraceContext**: `propagator/opentelemetry-propagator-b3/`
- **B3**: `propagator/opentelemetry-propagator-b3/`

## Summary

OpenTelemetry Python follows a clean architecture with:

1. **API/SDK Separation**: Libraries depend only on API, applications choose SDK
2. **Explicit Configuration**: Applications must set up SDK explicitly
3. **Pluggable Components**: Exporters, processors, samplers are all pluggable
4. **Context-Based**: Uses Python's contextvars for context propagation
5. **Library Instrumentation**: Uses decorators/wrappers, not bytecode manipulation
6. **Batch Processing**: Default BatchSpanProcessor for efficient export
7. **Standard Exporters**: OTLP, Zipkin, Console exporters available

The architecture is designed to be simple, explicit, and Pythonic, making it easy for developers to understand and customize their telemetry collection.
