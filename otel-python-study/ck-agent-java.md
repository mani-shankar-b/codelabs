# CK-Agent Java Architecture Documentation

## Overview

CK-Agent is a customized version of the OpenTelemetry Java agent that transforms traditional traces and spans into lightweight "CK spans" and emits metrics instead of heavy span objects. The agent builds complex domain graphs from distributed trace data while maintaining minimal overhead.

## Key Design Principles

1. **Lightweight Spans**: Replaces heavy OpenTelemetry span objects with minimal `CKSpan` instances
2. **Metrics-First**: Emits metrics instead of exporting span objects
3. **Graph-Based**: Builds domain graphs from trace data using Graph Path Elements (GPE)
4. **Zero Overhead When Disabled**: Conditional metric collection ensures no performance impact when instrumentation is disabled

## Architecture Components

### 1. Custom Span Implementation (CKSpan)

**Location**: `custom/src/main/java/com/codekarma/agent/span/CKSpan.java`

`CKSpan` is a lightweight replacement for OpenTelemetry's span objects:

- Implements `ReadWriteSpan` and `SpanData` interfaces for compatibility
- Stores minimal data:
  - Attributes (via `CKSpanAttributes`)
  - Timestamps (start/end)
  - Status code
  - Span kind
- No events, links, or full trace context (reduces memory footprint)

```java
public class CKSpan implements ReadWriteSpan, SpanData {
    private final CKSpanAttributes attributes;
    private SpanKind spanKind;
    private long startTime;
    private long endTime;
    private StatusCode statusCode;
    // Minimal implementation - no heavy objects
}
```

### 2. Span Suppression & Customization

**Location**: `custom/src/main/java/com/codekarma/agent/custom/CKAutoConfigurationCustomizerProvider.java`

The agent disables OpenTelemetry's default exporters and processors:

- **Noop Span Processor**: `CKNoopSpanProcessor` replaces standard span processors
- **Noop Exporters**: `CKNoopExporters` for span/metric/log exporters
- **Disabled Meter Provider**: Default metrics are disabled
- **Custom Propagator**: Uses `ck-route-propagator` instead of standard propagators

### 3. Instrumenter Interception

**Location**: `bootstrap/src/main/java/io/opentelemetry/instrumentation/api/instrumenter/Instrumenter.java`

The modified `Instrumenter` class intercepts all OpenTelemetry instrumentation:

#### How It Works

1. **Bootstrap Priority**: The modified `Instrumenter` is in the bootstrap classloader, loaded before application code
2. **Single Point of Control**: All instrumentation libraries use this modified `Instrumenter`
3. **CKSpan Creation**: When `start()` is called, it creates `CKSpan` instead of regular spans:

```java
private Context doCKStartImpl(Context parentContext, REQUEST request, Instant startTime) {
    CKSpanProvider ckSpanProvider = CKSpanProcessors.getCkSpanProvider();
    if (ckSpanProvider == null) {
        return parentContext;
    }
    
    // Create CKSpan instead of regular span
    Span ckSpan = ckSpanProvider.getSpanInstance(); // Returns new CKSpan()
    ckSpanProvider.setSpanKind(ckSpan, spanKind);
    ckSpanProvider.start(ckSpan, startTime);
    
    // Store in context (CKSpan implements Span interface)
    context = context.with(ckSpan);
    return ckSpanProvider.triggerOnstart(context, ckSpan);
}
```

4. **End Processing**: On `end()`, it processes the `CKSpan`:

```java
private void doCKEnd(Context context, REQUEST request, RESPONSE response, Throwable error, Instant endTime) {
    Span span = Span.fromContext(context);
    CKSpanProvider ckSpanProvider = CKSpanProcessors.getCkSpanProvider();
    
    if (ckSpanProvider == null || !ckSpanProvider.isValidInstance(span)) {
        return; // Not a CKSpan, skip
    }
    
    // Process attributes, status, etc.
    span.end(endTime);
    ckSpanProvider.triggerOnEnd(span); // Converts to GraphPathElement
}
```

#### Why This Works for All Libraries

- All OpenTelemetry instrumentations use `Instrumenter.builder()` to create instrumenters
- The modified `Instrumenter` is in the bootstrap classloader (loaded first)
- `CKSpan` implements the `Span` interface, so it's a drop-in replacement
- No changes needed in individual instrumentation libraries

### 4. Span to Graph Path Conversion

**Location**: `custom/src/main/java/com/codekarma/agent/processors/`

#### CKGraphSpanProcessor

Processes `CKSpan` lifecycle:
- **onStart()**: Sets path keys, attributes, and incoming path information
- **onEnd()**: Converts spans to Graph Path Elements (GPE) via `SGPNProcessor`

#### SGPNProcessor

Maps spans to Graph Path Elements using specialized mappers:
- **Database**: SQL, MongoDB, DynamoDB, Redis, Elasticsearch
- **Messaging**: Kafka, Pulsar, RabbitMQ, AWS SQS/SNS
- **RPC**: gRPC, HTTP
- **Optimized Lookup**: Uses static mapper instances for O(1) performance

```java
public void processOptimised(String incomingPathKey, ReadableSpan span) {
    SpanKind kind = span.getKind();
    SpanToGPEMapper mapper = performStaticLookup(span, kind);
    if (mapper != null) {
        GraphPathElement gpe = mapper.map(span);
        gpe.setLatencyNanos(span.getLatencyNanos());
        String pathKey = GraphPathInfo.addGraphPath(incomingPathKey, gpe);
    }
}
```

### 5. Metrics Emission

**Location**: `custom/src/main/java/com/codekarma/agent/custom/graph/GraphPathOTLPMetrics.java`

Instead of exporting spans, the agent emits metrics:

#### Metric Types

1. **Latency Percentiles** (Observable Gauge):
   - P50, P90, P95, P99
   - Uses HDRHistogram for accurate percentile calculations
   - Metric name: `ck_graph_latency`
   - Labels: `pathKey`, `quantile`

2. **Throughput** (Counter):
   - Metric name: `ck_graph_throughput`
   - Labels: `pathKey` (and optionally `incomingPathKey` for mixed paths)

3. **Error Count** (Counter):
   - Metric name: `ck_graph_error_count`
   - Labels: `pathKey`, `error_code`

#### Metric Collection

- Uses Observable Gauges for automatic collection during metric export
- HDRHistogram snapshots are taken periodically (default: 1 minute)
- Metrics are exported via OTLP gRPC to `CK_METRICS_ENDPOINT`

### 6. CK-Route Key and Context Propagation

**Location**: `custom/src/main/java/com.codekarma.agent.propagator/P.java`

#### What is CK-Route?

The `ck-route` key (constant `CK_ROUTE_KEY = "ck-route"`) is a header/property name used to propagate the current graph path across service boundaries.

#### Purpose

- **Context Propagation**: Carries a path key (hash) representing the current graph path
- **Graph Building**: Enables building domain graphs from distributed traces
- **Request Flow Tracking**: Tracks request flow through services, databases, and messaging systems

#### How It Works

1. **Path Key Generation**:
   - When a span ends, it's converted to a Graph Path Element (GPE)
   - GPE is added to the current graph path
   - SHA-256 hash is computed: `NodeHashGenerator.computeHashHex(appName + "|" + graphPathAsString)`
   - This hash becomes the path key stored in `ck-route`

2. **Context Propagation**:
   - Custom propagator (`P` class) implements `TextMapPropagator`
   - **inject()**: Extracts path key from OpenTelemetry Context and sets it in headers/properties
   - **extract()**: Reads `ck-route` from incoming headers/properties and sets it in Context

3. **Where It's Used**:
   - HTTP headers (Spring, Dropwizard)
   - Kafka message headers
   - RabbitMQ message headers
   - AWS SQS message attributes
   - AWS SNS message attributes
   - Pulsar message properties
   - gRPC metadata

#### Example Flow

```
1. HTTP Request arrives → Extract "ck-route" header → Set in Context
2. Process request → Create GraphPathElement → Add to graph path
3. Generate new path hash → Store in Context
4. Make downstream HTTP call → Inject "ck-route" header with new path hash
5. Send Kafka message → Add "ck-route" to message headers
```

#### Special Values

- `CK_GLITCH_KEY = "11111111111111111111111111111111"`: Used when no path key is available (fallback)

### 7. Initialization Flow

**Location**: `custom/src/main/java/com/codekarma/agent/custom/CKAgentListener.java`

```java
@Override
public void afterAgent(AutoConfiguredOpenTelemetrySdk autoConfiguredOpenTelemetrySdk) {
    CKSyncScheduler.initialize();
    AsyncProfilerManager.start();
    CKStackTraceProcessorFast.ensureInitialized();
    MethodInstrumentationConfigChangeListener.initialize();
    
    // Key initialization: Set CKSpanProvider
    CKSpanProcessors.setCkSpanProvider(new CKGraphSpanProvider());
    
    GraphPathInfo.init();
    ThreadLocalStackTraceStore.init();
}
```

### 8. Build Process

**Location**: `agent/build.gradle`

The agent is built as a multi-release JAR:

1. **Bootstrap Classes**: Modified OpenTelemetry classes in bootstrap classloader
2. **Custom Classes**: Agent-specific code in agent classloader
3. **Instrumentation**: Custom and upstream instrumentations
4. **Shadow/Relocation**: Packages are relocated to avoid conflicts

Key build steps:
- Bootstrap classes are placed in bootstrap classloader
- Modified `Instrumenter` takes precedence over upstream version
- All OpenTelemetry classes are shaded/relocated

## Data Flow

### Request Flow Example

```
1. HTTP Request arrives
   ↓
2. Extract "ck-route" header → Set in OpenTelemetry Context
   ↓
3. HTTP Server instrumentation intercepts
   ↓
4. Instrumenter.start() → doCKStartImpl()
   ↓
5. CKSpanProvider.getSpanInstance() → Creates CKSpan
   ↓
6. CKSpan stored in Context
   ↓
7. Request processing...
   ↓
8. Database call → Creates CLIENT CKSpan
   ↓
9. Instrumenter.end() → doCKEnd()
   ↓
10. CKSpan converted to GraphPathElement
   ↓
11. GraphPathElement added to graph path
   ↓
12. New path hash generated
   ↓
13. Metrics updated (latency, throughput, errors)
   ↓
14. Path hash propagated via "ck-route" header
```

### Span to Metrics Conversion

```
CKSpan (lightweight)
   ↓
CKGraphSpanProcessor.onEnd()
   ↓
SGPNProcessor.process()
   ↓
SpanToGPEMapper.map() → GraphPathElement
   ↓
GraphPathInfo.addGraphPath() → Path Key (hash)
   ↓
GraphPathOTLPMetrics.updateMetrics()
   ↓
HDRHistogram.recordValue() (latency)
LongAdder.add() (throughput/errors)
   ↓
Observable Gauge/Counter → OTLP Metrics
   ↓
OTLP gRPC Exporter → CK_METRICS_ENDPOINT
```

## Custom Instrumentation Module

**Location**: `instrumentation/`

The instrumentation module uses **ByteBuddy** to inject custom code into libraries at runtime. This allows the agent to add CK-specific functionality without modifying the original library code.

### How ByteBuddy Instrumentation Works

1. **Type Matching**: Identifies target classes to instrument
2. **Method Matching**: Selects specific methods to intercept
3. **Advice Injection**: Injects custom code before/after method execution
4. **Runtime Transformation**: Modifies bytecode at class loading time

### Instrumentation Pattern

Each instrumentation follows this pattern:

```java
@AutoService(InstrumentationModule.class)
public class MyInstrumentationModule extends CKModule {
    @Override
    public List<TypeInstrumentation> typeInstrumentations() {
        return Collections.singletonList(new MyTypeInstrumentation());
    }
}

public class MyTypeInstrumentation implements TypeInstrumentation {
    @Override
    public ElementMatcher<TypeDescription> typeMatcher() {
        return named("com.example.TargetClass");
    }
    
    @Override
    public void transform(TypeTransformer transformer) {
        transformer.applyAdviceToMethod(
            named("targetMethod"),
            this.getClass().getName() + "$MethodAdvice");
    }
    
    public static class MethodAdvice {
        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static void onEnter(@Advice.Argument(0) String arg) {
            // Custom code before method execution
        }
        
        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void onExit(@Advice.Return Object result) {
            // Custom code after method execution
        }
    }
}
```

### Examples of Custom Instrumentations

#### 1. Spring Web (DispatcherServlet)

**Location**: `instrumentation/spring/spring_v2/springwebv2/`

Instruments Spring's `DispatcherServlet` to:
- Extract `ck-route` header from incoming requests
- Create GraphPathElement for HTTP service endpoints
- Set path key in context
- Add `ck-route` header to response

```java
// Injects code into DispatcherServlet.doService() and getHandler()
transformer.applyAdviceToMethod(
    named("doService"),
    this.getClass().getName() + "$DoServiceAdvice");
```

#### 2. AWS SDK v2

**Location**: `instrumentation/aws/aws-sdk-2.22/aws-core/`

Instruments AWS SDK client builders to:
- Add custom `ExecutionInterceptor` to all AWS clients
- Process requests/responses to extract service information
- Add `ck-route` to SQS/SNS message attributes

```java
// Injects code into SdkDefaultClientBuilder.build()
@Advice.OnMethodEnter
public static void onBuild(@Advice.This Object builder) {
    AWSClientBuilderInstrumentationHelper.addExecutionInterceptors(
        builder, new TracingExecutionInterceptor());
}
```

#### 3. Kafka

**Location**: `instrumentation/kafka/kafka-overrides/`

Instruments Kafka consumers/producers to:
- Extract `ck-route` from message headers
- Handle batch processing with mixed topics/paths
- Create GraphPathElements for Kafka operations

Uses `ContextCustomizer` pattern to integrate with OpenTelemetry's Kafka instrumentation.

#### 4. RabbitMQ

**Location**: `instrumentation/rabbitmq/`

Instruments RabbitMQ `Channel` methods:
- `basicPublish()`: Adds `ck-route` header to messages
- `basicGet()`: Processes pull-based consumption
- `basicConsume()`: Wraps consumer with tracing delegate

```java
@Advice.OnMethodEnter
public static void onEnter(
    @Advice.Argument(0) String exchange,
    @Advice.Argument(1) String routingKey,
    @Advice.Argument(value = 4, readOnly = false) AMQP.BasicProperties props) {
    // Add ck-route header
    ckScope = CKRabbitMQProducerHelper.handleProcessPublish(
        exchange, routingKey, headers);
}
```

#### 5. Method Intelligence

**Location**: `instrumentation/method-intel/`

Instruments all methods in the application to:
- Track method entry/exit
- Build call stacks
- Enable CPU profiling and method-level metrics

```java
@Advice.OnMethodEnter
public static int onMethodEntry(@Advice.Origin("#t.#m#d") String methodSignature) {
    int methodDetailsHash = methodSignature.hashCode();
    int stackCount = ThreadLocalStackTraceStore.a(threadId, methodDetailsHash);
    return stackCount;
}
```

### Instrumentation Categories

1. **HTTP Frameworks**: Spring, Dropwizard
2. **Messaging**: Kafka, Pulsar, RabbitMQ, AWS SQS/SNS
3. **Databases**: MongoDB, Elasticsearch, JDBC, Redis, Aerospike
4. **Cloud Services**: AWS SDK v1/v2
5. **Method Intelligence**: Application-wide method tracking

### Integration with OpenTelemetry Instrumentation

The custom instrumentations work alongside OpenTelemetry's instrumentations:

1. **Override Pattern**: Some instrumentations override OpenTelemetry's classes (excluded in build)
2. **Context Customizer Pattern**: Use OpenTelemetry's `ContextCustomizer` API to add CK-specific logic
3. **Advice Pattern**: Direct ByteBuddy instrumentation for libraries not covered by OpenTelemetry

### Build Process

Custom instrumentations are:
1. Compiled and packaged into the agent JAR
2. Placed in `inst/` directory (isolated from application classpath)
3. Loaded by the agent's classloader
4. Applied at runtime when target classes are loaded

## Key Files Reference

### Core Components

- **CKSpan**: `custom/src/main/java/com/codekarma/agent/span/CKSpan.java`
- **CKGraphSpanProvider**: `custom/src/main/java/com/codekarma/agent/span/CKGraphSpanProvider.java`
- **Instrumenter**: `bootstrap/src/main/java/io/opentelemetry/instrumentation/api/instrumenter/Instrumenter.java`
- **CKGraphSpanProcessor**: `custom/src/main/java/com/codekarma/agent/processors/CKGraphSpanProcessor.java`
- **SGPNProcessor**: `custom/src/main/java/com/codekarma/agent/processors/SGPNProcessor.java`

### Metrics & Export

- **GraphPathOTLPMetrics**: `custom/src/main/java/com/codekarma/agent/custom/graph/GraphPathOTLPMetrics.java`
- **MetricSyncManager**: `custom/src/main/java/com/codekarma/agent/custom/platform/scheduled/MetricSyncManager.java`

### Context Propagation

- **Propagator**: `custom/src/main/java/com.codekarma.agent.propagator/P.java`
- **ContextHelpers**: `bootstrap/src/main/java/com/ck/agent/bootstrap/common/ContextHelpers.java`

### Configuration

- **CKAutoConfigurationCustomizerProvider**: `custom/src/main/java/com/codekarma/agent/custom/CKAutoConfigurationCustomizerProvider.java`
- **CKAgentListener**: `custom/src/main/java/com/codekarma/agent/custom/CKAgentListener.java`

### Instrumentation Examples

- **Spring**: `instrumentation/spring/spring_v2/springwebv2/DispatcherServletInstrumentation.java`
- **AWS SDK**: `instrumentation/aws/aws-sdk-2.22/aws-core/AwsClientBuilderInstrumentation.java`
- **Kafka**: `instrumentation/kafka/kafka-overrides/CKKafkaConsumerReceiveContextCustomizer.java`
- **RabbitMQ**: `instrumentation/rabbitmq/CKRabbitMQChannelInstrumentation.java`

## Configuration

### Required Environment Variables

- `CK_METRICS_ENDPOINT`: Endpoint for publishing metrics
- `CK_NEXUS_ENDPOINT`: Endpoint for Nexus to publish graph information

### Optional Environment Variables

- `CK_AGENT_LOG_LEVEL`: Log level (default: WARNING)
- `CK_METRICS_THRESHOLD`: Cardinality limit for observable counters

## Benefits

1. **Performance**: Lightweight spans reduce memory overhead
2. **Scalability**: Metrics are more efficient than exporting full span objects
3. **Graph Building**: Enables complex domain graph construction
4. **Zero Overhead**: Conditional collection when instrumentation is disabled
5. **Compatibility**: Works with all OpenTelemetry instrumentations without modification

## Summary

CK-Agent Java is a sophisticated customization of OpenTelemetry that:

1. **Intercepts** all instrumentation via modified `Instrumenter` in bootstrap classloader
2. **Injects** custom code into libraries using ByteBuddy for CK-specific functionality
3. **Replaces** heavy span objects with lightweight `CKSpan` instances
4. **Converts** spans to Graph Path Elements for domain graph building
5. **Emits** metrics instead of exporting span objects
6. **Propagates** graph path context via `ck-route` header across service boundaries

The architecture ensures that:
- Every library using OpenTelemetry instrumentation automatically uses `CKSpan` without requiring any changes to the instrumentation libraries themselves
- Custom instrumentations add CK-specific functionality (like `ck-route` propagation) directly into library code at runtime
- The combination of ByteBuddy instrumentation and Instrumenter interception provides comprehensive coverage across all libraries
