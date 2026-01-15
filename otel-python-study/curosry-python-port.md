# CK-Agent Python Port - Architecture and Implementation Guide

## Overview

This document outlines how to port the CK-Agent Java approach to Python, converting OpenTelemetry spans to metrics instead of exporting trace data. The Python SDK's architecture makes this implementation cleaner than Java, as it doesn't require modifying core SDK classes.

## Key Question: Can We Build Something Similar?

**Yes!** Python's OpenTelemetry SDK provides all the necessary interfaces to build a CK-Agent style system that:
- Converts spans to metrics instead of exporting traces
- Uses existing SDK interfaces (no core modifications needed)
- Works with zero-code instrumentation
- Maintains compatibility with all OpenTelemetry instrumentations

## Architecture Comparison

### Java CK-Agent Approach

1. **Modified Instrumenter**: Intercepts span creation in bootstrap classloader
2. **CKSpan Creation**: Creates lightweight `CKSpan` instead of regular spans
3. **Noop Exporters**: Suppresses default span/metric exporters
4. **Custom SpanProcessor**: Converts spans to GraphPathElements
5. **Custom Metrics**: Emits metrics via custom metric system

### Python Equivalent Approach

1. **Custom SpanProcessor**: Intercepts spans via `SpanProcessor.on_end()`
2. **Standard Spans**: Uses regular OpenTelemetry spans (no need for custom span class)
3. **No Span Exporters**: Simply don't add span exporters to TracerProvider
4. **Custom SpanProcessor**: Converts spans to metrics in `on_end()`
5. **Standard Metrics SDK**: Uses OpenTelemetry's standard `MeterProvider` and metrics API

## Implementation Architecture

### 1. Custom SpanProcessor (Core Component)

**Location**: Similar to `CKGraphSpanProcessor` in Java

The `SpanProcessor` interface is the perfect hook point - it's called on every span start and end:

```python
from opentelemetry.sdk.trace import SpanProcessor, ReadableSpan
from opentelemetry.metrics import get_meter_provider
from opentelemetry.trace.status import StatusCode
from collections import defaultdict
import threading
from typing import Optional
from opentelemetry import context as context_api

class CKMetricsSpanProcessor(SpanProcessor):
    """
    Converts spans to metrics instead of exporting them as traces.
    Similar to CKGraphSpanProcessor in Java.
    """
    
    def __init__(self):
        # Get meter from global MeterProvider
        self.meter = get_meter_provider().get_meter("ck-agent")
        
        # Create metrics instruments (similar to GraphPathOTLPMetrics)
        self.latency_histogram = self.meter.create_histogram(
            "ck_graph_latency",
            unit="ns",
            description="Latency percentiles for CK Graph paths"
        )
        
        self.throughput_counter = self.meter.create_counter(
            "ck_graph_throughput",
            description="Throughput data for CK Graph"
        )
        
        self.error_counter = self.meter.create_counter(
            "ck_graph_error_count",
            description="Error count for CK Graph paths"
        )
        
        # Store latency data for percentile calculation (similar to HDRHistogram)
        self._latency_data = defaultdict(list)
        self._lock = threading.Lock()
    
    def on_start(
        self,
        span: "Span",
        parent_context: Optional[context_api.Context] = None
    ) -> None:
        """
        Called when a span starts.
        Can extract path key, set attributes, etc.
        Similar to CKGraphSpanProcessor.onStart()
        """
        # Extract incoming path key from context or span attributes
        # Set path-related attributes
        pass
    
    def on_end(self, span: ReadableSpan) -> None:
        """
        Called when a span ends.
        Converts span data to metrics.
        Similar to CKGraphSpanProcessor.onEnd() -> SGPNProcessor.process()
        """
        if not (span.context and span.context.trace_flags.sampled):
            return
        
        # Extract path key from span attributes (similar to ck-route)
        path_key = span.attributes.get("ck.path_key") or "unknown"
        
        # Calculate latency in nanoseconds
        latency_ns = span.end_time - span.start_time
        
        # Record latency histogram (for percentile calculation)
        self.latency_histogram.record(
            latency_ns,
            attributes={
                "path_key": path_key,
                "span_kind": span.kind.name if span.kind else "INTERNAL",
            }
        )
        
        # Record throughput counter
        self.throughput_counter.add(
            1,
            attributes={"path_key": path_key}
        )
        
        # Record errors if any
        if span.status and span.status.status_code == StatusCode.ERROR:
            error_code = span.status.description or "CK_ERROR"
            self.error_counter.add(
                1,
                attributes={
                    "path_key": path_key,
                    "error_code": error_code
                }
            )
    
    def shutdown(self) -> None:
        """Cleanup on shutdown"""
        pass
    
    def force_flush(self, timeout_millis: int = 30000) -> bool:
        """Flush pending metrics"""
        return True
```

### 2. Configuration Setup

**Suppress Span Exporters** (Similar to `CKAutoConfigurationCustomizerProvider`):

```python
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource
import os

def setup_ck_agent():
    """
    Setup CK-Agent style configuration:
    - No span exporters (spans converted to metrics)
    - Custom SpanProcessor converts spans to metrics
    - Metrics exported via OTLP
    """
    
    # 1. Create TracerProvider WITHOUT span exporters
    tracer_provider = TracerProvider(
        resource=Resource.create({
            "service.name": os.getenv("OTEL_SERVICE_NAME", "unknown-service"),
        })
    )
    
    # 2. Add ONLY our custom metrics processor (NO span exporters)
    ck_processor = CKMetricsSpanProcessor()
    tracer_provider.add_span_processor(ck_processor)
    
    # 3. Set as global tracer provider
    trace.set_tracer_provider(tracer_provider)
    
    # 4. Configure Metrics SDK to export metrics
    metric_exporter = OTLPMetricExporter(
        endpoint=os.getenv("CK_METRICS_ENDPOINT", "http://localhost:4317")
    )
    metric_reader = PeriodicExportingMetricReader(
        metric_exporter,
        export_interval_millis=60000  # 1 minute
    )
    
    meter_provider = MeterProvider(
        resource=Resource.create({
            "service.name": os.getenv("OTEL_SERVICE_NAME", "unknown-service"),
        }),
        metric_readers=[metric_reader]
    )
    metrics.set_meter_provider(meter_provider)
    
    return tracer_provider, meter_provider
```

### 3. Graph Path Building (Optional)

If you need graph path building similar to Java:

```python
class GraphPathBuilder:
    """
    Builds graph paths from spans, similar to SGPNProcessor in Java.
    Converts spans to GraphPathElements and generates path keys.
    """
    
    def __init__(self):
        self.path_cache = {}  # Cache of path_key -> GraphPathElement
    
    def process_span(self, span: ReadableSpan, incoming_path_key: str = None) -> str:
        """
        Process span and return new path key.
        Similar to SGPNProcessor.process()
        """
        # Extract span attributes
        span_kind = span.kind
        attributes = span.attributes
        
        # Map span to GraphPathElement based on attributes
        # (Similar to SpanToGPEMapper in Java)
        gpe = self._map_span_to_gpe(span, attributes)
        
        if not gpe:
            return incoming_path_key
        
        # Add to graph path and generate new path key
        # (Similar to GraphPathInfo.addGraphPath())
        new_path_key = self._add_to_path(incoming_path_key, gpe)
        
        return new_path_key
    
    def _map_span_to_gpe(self, span: ReadableSpan, attributes: dict):
        """Map span to GraphPathElement based on attributes"""
        span_kind = span.kind
        
        # Database spans
        if attributes.get("db.system"):
            db_system = attributes.get("db.system")
            if db_system == "postgresql":
                return DatabaseGPE(db_system, attributes.get("db.name"))
            # ... other databases
        
        # HTTP spans
        if attributes.get("http.method"):
            return HTTPServiceGPE(
                attributes.get("http.method"),
                attributes.get("http.route")
            )
        
        # Messaging spans
        if attributes.get("messaging.system"):
            messaging_system = attributes.get("messaging.system")
            if messaging_system == "kafka":
                return KafkaConsumerGPE(
                    attributes.get("messaging.kafka.consumer.group"),
                    attributes.get("messaging.destination.name")
                )
        
        return None
    
    def _add_to_path(self, incoming_path: str, gpe) -> str:
        """Add GPE to path and generate hash"""
        # Build path string
        path_string = f"{incoming_path}|{gpe.to_string()}" if incoming_path else gpe.to_string()
        
        # Generate hash (similar to NodeHashGenerator.computeHashHex)
        import hashlib
        path_key = hashlib.sha256(path_string.encode()).hexdigest()
        
        # Cache for later use
        self.path_cache[path_key] = gpe
        
        return path_key
```

### 4. Enhanced SpanProcessor with Graph Paths

```python
class CKMetricsSpanProcessor(SpanProcessor):
    """Enhanced version with graph path building"""
    
    def __init__(self):
        self.meter = get_meter_provider().get_meter("ck-agent")
        self.path_builder = GraphPathBuilder()
        
        # Create metrics
        self.latency_histogram = self.meter.create_histogram(
            "ck_graph_latency",
            unit="ns",
            description="Latency percentiles for CK Graph paths"
        )
        self.throughput_counter = self.meter.create_counter(
            "ck_graph_throughput",
            description="Throughput data for CK Graph"
        )
        self.error_counter = self.meter.create_counter(
            "ck_graph_error_count",
            description="Error count for CK Graph paths"
        )
    
    def on_start(self, span: "Span", parent_context: Optional[Context] = None):
        """Extract incoming path key from context"""
        # Extract ck-route from context (similar to ContextHelpers.getPathFromContext)
        incoming_path = self._extract_path_from_context(parent_context)
        if incoming_path:
            span.set_attribute("ck.incoming_path", incoming_path)
    
    def on_end(self, span: ReadableSpan) -> None:
        if not (span.context and span.context.trace_flags.sampled):
            return
        
        # Get incoming path key
        incoming_path = span.attributes.get("ck.incoming_path")
        
        # Build graph path (similar to SGPNProcessor)
        path_key = self.path_builder.process_span(span, incoming_path)
        
        if not path_key:
            return
        
        # Calculate latency
        latency_ns = span.end_time - span.start_time
        
        # Record metrics with path_key
        self.latency_histogram.record(
            latency_ns,
            attributes={"path_key": path_key}
        )
        
        self.throughput_counter.add(
            1,
            attributes={"path_key": path_key}
        )
        
        if span.status and span.status.status_code == StatusCode.ERROR:
            error_code = span.status.description or "CK_ERROR"
            self.error_counter.add(
                1,
                attributes={
                    "path_key": path_key,
                    "error_code": error_code
                }
            )
    
    def _extract_path_from_context(self, context: Optional[Context]) -> Optional[str]:
        """Extract ck-route from context"""
        if context is None:
            return None
        # Use context.get() to retrieve ck-route value
        # Similar to ContextHelpers.getPathFromContext in Java
        return context.get("ck.route") if hasattr(context, 'get') else None
```

### 5. Integration with Zero-Code Instrumentation

To work with `opentelemetry-instrument`, create a custom distro:

```python
# ck_distro/__init__.py
from opentelemetry.sdk._configuration import _BaseConfigurator
from opentelemetry.sdk._configuration import _initialize_components
from ck_agent import CKMetricsSpanProcessor

class CKDistroConfigurator(_BaseConfigurator):
    """
    Custom configurator that:
    1. Suppresses default span exporters
    2. Adds CKMetricsSpanProcessor
    3. Configures metrics export
    """
    
    def _configure(self, **kwargs):
        # Suppress span exporters
        kwargs['trace_exporter_names'] = []
        
        # Initialize components (but we'll override span processors)
        _initialize_components(**kwargs)
        
        # Get the TracerProvider that was just created
        from opentelemetry import trace
        tracer_provider = trace.get_tracer_provider()
        
        # Remove any default processors and add ours
        if hasattr(tracer_provider, '_span_processors'):
            tracer_provider._span_processors.clear()
        
        # Add our custom processor
        ck_processor = CKMetricsSpanProcessor()
        tracer_provider.add_span_processor(ck_processor)
```

Then register it via entry points in `pyproject.toml`:

```toml
[project.entry-points.opentelemetry_distro]
ck_distro = "ck_distro:CKDistroConfigurator"
```

## Key Advantages of Python Approach

### 1. **No Core Modifications Required**

Unlike Java where you need to modify `Instrumenter` in bootstrap classloader, Python only requires:
- Custom `SpanProcessor` implementation
- Configuration that doesn't add span exporters

### 2. **Standard SDK Interfaces**

- Use standard `SpanProcessor` interface (no custom classes needed)
- Use standard `MeterProvider` and metrics API
- No need for custom span classes (regular spans work fine)

### 3. **Simpler Architecture**

- **Java**: Modified Instrumenter → CKSpan → CKGraphSpanProcessor → SGPNProcessor → Metrics
- **Python**: Standard Spans → CKMetricsSpanProcessor → Metrics SDK

### 4. **Works with Zero-Code Instrumentation**

- Can be integrated via custom distro
- Works with `opentelemetry-instrument` command
- No application code changes needed

## Comparison Table

| Aspect | Java CK-Agent | Python Equivalent |
|--------|---------------|-------------------|
| **Span Interception** | Modified `Instrumenter` in bootstrap | Custom `SpanProcessor` |
| **Span Class** | Custom `CKSpan` (lightweight) | Standard `Span` (works as-is) |
| **Span Suppression** | Noop exporters/processors | Don't add span exporters |
| **Span Processing** | `CKGraphSpanProcessor` → `SGPNProcessor` | `CKMetricsSpanProcessor` |
| **Graph Path Building** | Custom `GraphPathElement` system | Can implement similar in Python |
| **Metrics Emission** | Custom metrics system | Standard `MeterProvider` API |
| **Metrics Types** | Custom ObservableGauge/Counter | Standard Histogram/Counter |
| **Context Propagation** | Custom `ck-route` propagator | Can add custom propagator |
| **Configuration** | `CKAutoConfigurationCustomizerProvider` | Custom distro configurator |
| **Zero-Code Support** | Via agent JAR | Via custom distro package |

## Implementation Steps

### Step 1: Create Custom SpanProcessor

1. Implement `SpanProcessor` interface
2. In `on_end()`, extract span data
3. Convert to metrics using `MeterProvider`
4. Record latency, throughput, errors

### Step 2: Suppress Span Exporters

1. Don't add `BatchSpanProcessor` with span exporters
2. Only add your custom `CKMetricsSpanProcessor`
3. Configure via distro or programmatic setup

### Step 3: Configure Metrics Export

1. Set up `MeterProvider` with OTLP exporter
2. Use `PeriodicExportingMetricReader` for automatic export
3. Configure endpoint via `CK_METRICS_ENDPOINT`

### Step 4: Path Key Extraction (Optional)

1. Extract `ck-route` from span attributes or context
2. Build graph path similar to Java implementation
3. Generate path hash for metrics labels

### Step 5: Integration

1. Create custom distro package
2. Register configurator via entry points
3. Use with `opentelemetry-instrument` or programmatic setup

## Example: Complete Implementation

```python
# ck_agent/__init__.py
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider, SpanProcessor
from opentelemetry.sdk.trace import ReadableSpan
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.trace.status import StatusCode
import os

class CKMetricsSpanProcessor(SpanProcessor):
    def __init__(self):
        self.meter = get_meter_provider().get_meter("ck-agent")
        self.latency_histogram = self.meter.create_histogram(
            "ck_graph_latency", unit="ns"
        )
        self.throughput_counter = self.meter.create_counter(
            "ck_graph_throughput"
        )
        self.error_counter = self.meter.create_counter(
            "ck_graph_error_count"
        )
    
    def on_start(self, span, parent_context=None):
        pass
    
    def on_end(self, span: ReadableSpan):
        if not (span.context and span.context.trace_flags.sampled):
            return
        
        path_key = span.attributes.get("ck.path_key", "unknown")
        latency_ns = span.end_time - span.start_time
        
        self.latency_histogram.record(latency_ns, {"path_key": path_key})
        self.throughput_counter.add(1, {"path_key": path_key})
        
        if span.status and span.status.status_code == StatusCode.ERROR:
            error_code = span.status.description or "CK_ERROR"
            self.error_counter.add(1, {
                "path_key": path_key,
                "error_code": error_code
            })

def configure_ck_agent():
    """Configure CK-Agent style setup"""
    # TracerProvider with NO span exporters
    tracer_provider = TracerProvider()
    tracer_provider.add_span_processor(CKMetricsSpanProcessor())
    trace.set_tracer_provider(tracer_provider)
    
    # MeterProvider for metrics export
    metric_exporter = OTLPMetricExporter(
        endpoint=os.getenv("CK_METRICS_ENDPOINT", "http://localhost:4317")
    )
    metric_reader = PeriodicExportingMetricReader(metric_exporter)
    meter_provider = MeterProvider(metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)
```

## Usage

### Programmatic Setup

```python
from ck_agent import configure_ck_agent

# Configure before importing instrumented libraries
configure_ck_agent()

# Now use your application - spans will be converted to metrics
import flask
# ... rest of your app
```

### With Zero-Code Instrumentation

```bash
# Install custom distro
pip install ck-opentelemetry-distro

# Use with opentelemetry-instrument
CK_METRICS_ENDPOINT=http://metrics:4317 \
opentelemetry-instrument python myapp.py
```

## Key Differences from Java

### 1. **No Bootstrap Modification**

- **Java**: Must modify `Instrumenter` in bootstrap classloader
- **Python**: Just implement `SpanProcessor` interface

### 2. **No Custom Span Class Needed**

- **Java**: Created lightweight `CKSpan` to reduce memory
- **Python**: Standard spans work fine (Python's object model is different)

### 3. **Simpler Hook Point**

- **Java**: Modified `Instrumenter.start()` and `Instrumenter.end()`
- **Python**: `SpanProcessor.on_start()` and `SpanProcessor.on_end()`

### 4. **Standard Metrics API**

- **Java**: Custom metrics system with `GenericMetricsUpdater`
- **Python**: Use standard OpenTelemetry metrics API

### 5. **No Bytecode Manipulation**

- **Java**: Uses ByteBuddy for library instrumentation
- **Python**: Uses monkey-patching (simpler, but less powerful)

## Challenges and Considerations

### 1. **Percentile Calculation**

Java uses HDRHistogram for accurate percentiles. Python options:
- Use `Histogram` with explicit bucket boundaries
- Use external library like `hdrhistogram` (Python port)
- Calculate percentiles from stored latency samples

### 2. **Graph Path Building**

Java has sophisticated `SGPNProcessor` with mappers. Python would need:
- Similar mapper system for different span types
- Path key generation and caching
- Graph path element classes

### 3. **Context Propagation**

Java has custom `ck-route` propagator. Python would need:
- Custom `TextMapPropagator` implementation
- Integration with `opentelemetry-instrument`
- Header/property injection for different protocols

### 4. **Performance**

- Python's GIL may affect concurrent processing
- Consider async/threading for metric collection
- Batch metric updates if needed

## Conclusion

Yes, you can absolutely build a CK-Agent style system in Python using existing SDK interfaces. The Python approach is actually **cleaner** than Java because:

1. **No core modifications needed** - just implement standard interfaces
2. **Standard metrics API** - use existing MeterProvider
3. **Simpler architecture** - SpanProcessor is a perfect hook point
4. **Works with zero-code** - can be integrated via distro

The main implementation work involves:
1. Creating `CKMetricsSpanProcessor` to convert spans to metrics
2. Suppressing default span exporters
3. Configuring metrics export
4. (Optional) Building graph path system similar to Java

This approach maintains compatibility with all OpenTelemetry instrumentations while converting spans to metrics instead of exporting traces.
