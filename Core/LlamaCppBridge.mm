// LlamaCppBridge_Fixed.mm
// Real inference implementation with corrected modern llama.cpp API
// COPIED FROM WORKING APP - Only change: Accept pre-formatted prompt (CAG builds it)

#import "LlamaCppBridge.h"
#include "llama.h"
#include <string>
#include <vector>
#include <thread>
#include <sstream>

@interface LlamaCppBridge () {
    llama_model *model;
    llama_context *ctx;
    llama_model_params model_params;
    llama_context_params ctx_params;
    std::string modelPath;
    std::string systemPrompt;
    bool shouldStop;
    NSMutableString *streamingResponse; // Accumulate streaming response
}
@end

@implementation LlamaCppBridge

@synthesize isModelLoaded = _isModelLoaded;
@synthesize loadingProgress = _loadingProgress;

- (instancetype)initWithModelPath:(NSString *)path {
#ifdef DEBUG
    NSLog(@"🚀 LlamaCppBridge (Real Inference) init");
#endif
    self = [super init];
    if (self) {
        modelPath = std::string([path UTF8String]);
        _isModelLoaded = NO;
        _loadingProgress = 0.0;
        shouldStop = false;
        systemPrompt = "You are Corra, a helpful AI assistant specializing in clinical trials and medical research.";
        
        // Initialize llama backend
        llama_backend_init();
    }
    return self;
}

- (instancetype)initWithModelPath:(NSString *)path
                      contextSize:(int32_t)contextSize
                        gpuLayers:(int32_t)gpuLayers
                         useMlock:(BOOL)useMlock {
    self = [self initWithModelPath:path];
    if (self) {
        ctx_params = llama_context_default_params();
        ctx_params.n_ctx = contextSize;
        ctx_params.n_threads = (int32_t)std::thread::hardware_concurrency() / 2;
        ctx_params.n_threads_batch = ctx_params.n_threads;
    }
    return self;
}

- (void)setSystemPrompt:(NSString *)prompt {
    systemPrompt = std::string([prompt UTF8String]);
}

- (void)setContextSize:(int32_t)contextSize {
    ctx_params.n_ctx = contextSize;
}

- (BOOL)loadModelWithError:(NSError **)error {
#ifdef DEBUG
    NSLog(@"🔄 Loading model for REAL INFERENCE...");
#endif
    
    // Check if file exists
    NSString *pathStr = [NSString stringWithUTF8String:modelPath.c_str()];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:pathStr]) {
#ifdef DEBUG
        NSLog(@"❌ Model file does not exist");
#endif
        if (error) {
            *error = [NSError errorWithDomain:@"LlamaCppBridge"
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Model file does not exist"}];
        }
        return NO;
    }
    
    _loadingProgress = 0.1;
    
    // Strategy: Try Metal-first approach with CPU fallback
    // Model parameters - try Metal first
    model_params = llama_model_default_params();
    model_params.n_gpu_layers = 29; // EXPLICIT: All 29 layers like MacBook (not -1)
    model_params.use_mmap = true;
    model_params.use_mlock = false;
    
    model = llama_model_load_from_file(modelPath.c_str(), model_params);
    
    if (!model) {
#ifdef DEBUG
        NSLog(@"⚠️ Metal-first failed, trying CPU-only...");
#endif
        // Conservative fallback - still try to keep output layer on GPU
        model_params.n_gpu_layers = 28; // Keep most layers on GPU including near-output layers
        model_params.use_mmap = true;
        model = llama_model_load_from_file(modelPath.c_str(), model_params);
        
        if (!model) {
#ifdef DEBUG
            NSLog(@"❌ Both Metal and CPU loading failed");
#endif
            if (error) {
                *error = [NSError errorWithDomain:@"LlamaCppBridge"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Model loading failed on both Metal and CPU"}];
            }
            return NO;
        }
#ifdef DEBUG
        NSLog(@"✅ CPU-only loading succeeded");
#endif
    } else {
#ifdef DEBUG
        NSLog(@"✅ Metal-first loading succeeded");
#endif
    }
    
    _loadingProgress = 0.5;
    
    // Context parameters - MATCH WORKING APP EXACTLY (2048 context)
    ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 2048;    // Match working app exactly
    ctx_params.n_batch = 512;   // CRITICAL: Match MacBook's 512 (not 2048!)
    ctx_params.n_ubatch = 512;  // Match MacBook
    ctx_params.n_threads = 0;   // Auto-detect like MacBook
    ctx_params.n_threads_batch = 0; // Auto-detect like MacBook
    
    // CRITICAL: Unified Metal KV cache like MacBook
    ctx_params.type_k = GGML_TYPE_F16; // FP16 K cache
    ctx_params.type_v = GGML_TYPE_F16; // FP16 V cache
    
    // Flash attention - keep disabled (working on both platforms)
    ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
    
#ifdef DEBUG
    NSLog(@"🔧 Creating context with %d context size, %d threads", ctx_params.n_ctx, ctx_params.n_threads);
#endif
    
    // Create context using modern API
    ctx = llama_init_from_model(model, ctx_params);
    if (!ctx) {
#ifdef DEBUG
        NSLog(@"❌ Failed to create context");
#endif
        llama_model_free(model);
        model = nullptr;
        if (error) {
            *error = [NSError errorWithDomain:@"LlamaCppBridge"
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to create llama context"}];
        }
        return NO;
    }
    
    _loadingProgress = 1.0;
    _isModelLoaded = YES;
#ifdef DEBUG
    NSLog(@"✅ Model and context loaded successfully for REAL INFERENCE");
#endif
    return YES;
}

- (NSString *)generateResponse:(NSString *)forPrompt maxTokens:(int32_t)maxTokens temperature:(float)temperature {
    if (!_isModelLoaded || !ctx || !model) {
        return @"Error: Model is not loaded.";
    }
    
    shouldStop = false;
    
    // CRITICAL FIX: Recreate context for each new conversation (like web app does)
    static int conversation_id = 0;
    conversation_id++;
    
    if (conversation_id > 1) {
        // Recreate context to ensure completely fresh state
        llama_free(ctx);
        ctx = llama_init_from_model(model, ctx_params);
        if (!ctx) {
            return @"Error: Failed to reset conversation state";
        }
    }
    
    // Get model vocab
    const struct llama_vocab* vocab = llama_model_get_vocab(model);
    if (!vocab) {
        return @"Error: Could not get model vocabulary.";
    }
    
    // CAG PROMPT: Use prompt as-is (CAGManager already built it with chat template)
    std::string fullPrompt = std::string([forPrompt UTF8String]);
    
    // Tokenize the prompt
    std::vector<llama_token> tokens;
    tokens.resize(fullPrompt.length() + 100);
    
    int32_t n_tokens = llama_tokenize(
        vocab,
        fullPrompt.c_str(),
        static_cast<int32_t>(fullPrompt.length()),
        tokens.data(),
        static_cast<int32_t>(tokens.size()),
        true,  // add_special
        true   // parse_special
    );
    
    if (n_tokens < 0) {
        return @"Error: Failed to tokenize prompt";
    }
    tokens.resize(n_tokens);
    
#ifdef DEBUG
    NSLog(@"🔤 Tokenized prompt: %d tokens", n_tokens);
#endif
    
    // Create batch for processing
    llama_batch batch = llama_batch_init(n_tokens, 0, 1);
    
    // Add tokens to batch manually (since llama_batch_add might not exist)
    for (int i = 0; i < n_tokens; i++) {
        batch.token[i] = tokens[i];
        batch.pos[i] = i;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i] = (i == n_tokens - 1) ? 1 : 0; // Only last token needs logits
    }
    batch.n_tokens = n_tokens;
    
    // Process the prompt
    if (llama_decode(ctx, batch) != 0) {
#ifdef DEBUG
        NSLog(@"❌ Failed to decode prompt batch");
#endif
        llama_batch_free(batch);
        return @"Error: Failed to process prompt";
    }
    
    // Generate response tokens
    std::string response;
    int32_t n_generated = 0;
    
    while (n_generated < maxTokens && !shouldStop) {
        // Get logits for the last token
        float* logits = llama_get_logits_ith(ctx, -1);
        if (!logits) {
            break;
        }
        
        // Create candidates array - use modern vocab API
        int32_t n_vocab = llama_vocab_n_tokens(vocab);
        std::vector<llama_token_data> candidates;
        candidates.reserve(n_vocab);
        
        for (int32_t i = 0; i < n_vocab; i++) {
            candidates.emplace_back(llama_token_data{i, logits[i], 0.0f});
        }
        
        llama_token_data_array candidates_p = {candidates.data(), candidates.size(), false};
        
        // Apply temperature - use sampler API if available
        // Since llama_sample_temp might not exist, we'll use a simpler approach
        llama_token next_token;
        if (temperature > 0.0f) {
            // Simple temperature sampling fallback
            for (size_t i = 0; i < candidates.size(); i++) {
                candidates[i].logit /= temperature;
            }
            // Find max logit for softmax stability
            float max_logit = candidates[0].logit;
            for (size_t i = 1; i < candidates.size(); i++) {
                if (candidates[i].logit > max_logit) {
                    max_logit = candidates[i].logit;
                }
            }
            // Apply softmax and sample
            float sum = 0.0f;
            for (size_t i = 0; i < candidates.size(); i++) {
                candidates[i].p = expf(candidates[i].logit - max_logit);
                sum += candidates[i].p;
            }
            float r = static_cast<float>(rand()) / RAND_MAX * sum;
            float cumsum = 0.0f;
            next_token = candidates[0].id;
            for (size_t i = 0; i < candidates.size(); i++) {
                cumsum += candidates[i].p;
                if (cumsum >= r) {
                    next_token = candidates[i].id;
                    break;
                }
            }
        } else {
            // Greedy sampling - find max logit
            next_token = candidates[0].id;
            float max_logit = candidates[0].logit;
            for (size_t i = 1; i < candidates.size(); i++) {
                if (candidates[i].logit > max_logit) {
                    max_logit = candidates[i].logit;
                    next_token = candidates[i].id;
                }
            }
        }
        
        // AUTOMATIC EOS DETECTION: Replicate Python wrapper's natural stopping behavior
        // Check for any EOG (End of Generation) tokens that indicate natural completion
        if (next_token == 128001 ||  // <|end_of_text|> - Natural completion
            next_token == 128008 ||  // <|eom_id|> - End of message
            next_token == 128009) {  // <|eot_id|> - End of turn
            break; // Respect the LLM's natural stopping point
        }
        
        // Convert token to text using modern API
        char token_str[256];
        int32_t token_len = llama_token_to_piece(vocab, next_token, token_str, sizeof(token_str), 0, false);
        
        if (token_len > 0) {
            token_str[token_len] = '\0';
            std::string token_text(token_str);
            
            // STRICT: Check for any conversation patterns that indicate fake dialogue
            if (token_text.find("User:") != std::string::npos || 
                token_text.find("user:") != std::string::npos ||
                token_text.find("Human:") != std::string::npos ||
                token_text.find("Question:") != std::string::npos ||
                token_text.find("I'm considering participating") != std::string::npos ||  // More specific patterns
                token_text.find("I've heard mixed reviews") != std::string::npos) {
                break; // Stop if LLM tries to generate fake conversations
            }
            
            response += token_text;
        }
        
        // Prepare next batch with the new token
        batch.n_tokens = 1;
        batch.token[0] = next_token;
        batch.pos[0] = n_tokens + n_generated;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = 1;
        
        // Decode the new token
        if (llama_decode(ctx, batch) != 0) {
            break;
        }
        
        n_generated++;
    }
    
    llama_batch_free(batch);
    
    if (response.empty()) {
        return @"I'm sorry, I couldn't generate a response. Please try again.";
    }
    
    return [NSString stringWithUTF8String:response.c_str()];
}

- (NSString *)generateResponseForPrompt:(NSString *)prompt maxTokens:(int32_t)maxTokens temperature:(float)temperature {
    return [self generateResponse:prompt maxTokens:maxTokens temperature:temperature];
}

// STREAMING IMPLEMENTATION: Real-time token generation
- (void)generateStreamingResponseForPrompt:(NSString *)prompt 
                                 maxTokens:(int32_t)maxTokens 
                               temperature:(float)temperature {
    if (!_isModelLoaded || !ctx || !model) {
        if (self.streamingDelegate) {
            [self.streamingDelegate llamaBridge:self didCompleteWithResponse:@"Error: Model is not loaded."];
        }
        return;
    }
    
    shouldStop = false;
    streamingResponse = [[NSMutableString alloc] init];
    
    // CRITICAL FIX: Recreate context for each new conversation (like web app does)
    static int streaming_conversation_id = 0;
    streaming_conversation_id++;
    
    if (streaming_conversation_id > 1) {
        // Recreate context to ensure completely fresh state
        llama_free(ctx);
        ctx = llama_init_from_model(model, ctx_params);
        if (!ctx) {
            if (self.streamingDelegate) {
                [self.streamingDelegate llamaBridge:self didCompleteWithResponse:@"Error: Failed to reset conversation state"];
            }
            return;
        }
    }
    
    // Get model vocab
    const struct llama_vocab* vocab = llama_model_get_vocab(model);
    if (!vocab) {
        if (self.streamingDelegate) {
            [self.streamingDelegate llamaBridge:self didCompleteWithResponse:@"Error: Could not get model vocabulary."];
        }
        return;
    }
    
    // CAG PROMPT: Use prompt as-is (CAGManager already built it with chat template)
    std::string fullPrompt = std::string([prompt UTF8String]);
    
    // Tokenize the prompt
    std::vector<llama_token> tokens;
    tokens.resize(fullPrompt.length() + 100);
    
    int32_t n_tokens = llama_tokenize(
        vocab,
        fullPrompt.c_str(),
        static_cast<int32_t>(fullPrompt.length()),
        tokens.data(),
        static_cast<int32_t>(tokens.size()),
        true,   // add_special
        true    // parse_special
    );
    
    if (n_tokens < 0) {
        if (self.streamingDelegate) {
            [self.streamingDelegate llamaBridge:self didCompleteWithResponse:@"Error: Tokenization failed"];
        }
        return;
    }
    
    tokens.resize(n_tokens);
    
    // CAG PROMPT TRUNCATION: If prompt exceeds context, truncate intelligently
    // Keep system prompt + user question, truncate knowledge chunks if needed
    int32_t max_context_tokens = ctx_params.n_ctx;
    if (n_tokens > max_context_tokens) {
#ifdef DEBUG
        NSLog(@"⚠️ CAG prompt exceeds context size, truncating...");
#endif
        
        // Find where user question starts (after "<|start_header_id|>user<|end_header_id|>")
        // Keep system prompt + user question, truncate knowledge if present
        std::string promptStr = std::string([prompt UTF8String]);
        size_t userStart = promptStr.find("<|start_header_id|>user<|end_header_id|>");
        
        if (userStart != std::string::npos) {
            // Tokenize just system + user parts to see their size
            std::string systemUserPart = promptStr.substr(0, userStart + std::string("<|start_header_id|>user<|end_header_id|>\n\n").length());
            std::string userQuestion = promptStr.substr(userStart + std::string("<|start_header_id|>user<|end_header_id|>\n\n").length());
            
            // Find end of user question
            size_t userEnd = userQuestion.find("<|eot_id|>");
            if (userEnd != std::string::npos) {
                userQuestion = userQuestion.substr(0, userEnd);
            }
            
            // Rebuild with minimal system prompt (no knowledge) if needed
            std::string minimalSystem = "<|start_header_id|>system<|end_header_id|>\n\n"
                "You are Corra, a friendly and knowledgeable AI assistant who specializes in clinical trials.\n"
                "Answer questions about clinical trials clearly and simply.<|eot_id|>";
            
            std::string minimalPrompt = minimalSystem
                + "<|start_header_id|>user<|end_header_id|>\n\n"
                + userQuestion
                + "<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n";
            
            // Re-tokenize minimal prompt
            tokens.resize(minimalPrompt.length() + 100);
            n_tokens = llama_tokenize(
                vocab,
                minimalPrompt.c_str(),
                static_cast<int32_t>(minimalPrompt.length()),
                tokens.data(),
                static_cast<int32_t>(tokens.size()),
                true,
                true
            );
            
            if (n_tokens > 0 && n_tokens <= max_context_tokens) {
                tokens.resize(n_tokens);
            } else {
                // Still too large - truncate user question
                int32_t maxUserTokens = max_context_tokens - 100; // Reserve space for system
                tokens.resize(maxUserTokens);
                n_tokens = llama_tokenize(
                    vocab,
                    minimalPrompt.c_str(),
                    static_cast<int32_t>(minimalPrompt.length()),
                    tokens.data(),
                    maxUserTokens,
                    true,
                    true
                );
                if (n_tokens < 0) n_tokens = -n_tokens;
                tokens.resize(n_tokens);
            }
        } else {
            // Fallback: simple truncation
            int32_t maxTokens = max_context_tokens - 4; // Reserve space
            if (n_tokens > maxTokens) {
                tokens.resize(maxTokens);
                n_tokens = maxTokens;
            }
        }
    }
    
    // Process prompt in chunks if needed (for large CAG prompts)
    int32_t batch_size = ctx_params.n_batch;
    int32_t chunk_size = std::min(n_tokens, batch_size);
    
    // Process prompt in chunks if needed
    for (int32_t chunk_start = 0; chunk_start < n_tokens; chunk_start += chunk_size) {
        int32_t chunk_end = std::min(chunk_start + chunk_size, n_tokens);
        int32_t chunk_tokens = chunk_end - chunk_start;
        
        llama_batch batch = llama_batch_init(chunk_tokens, 0, 1);
        batch.n_tokens = chunk_tokens;
        
        for (int32_t i = 0; i < chunk_tokens; i++) {
            int32_t token_idx = chunk_start + i;
            batch.token[i] = tokens[token_idx];
            batch.pos[i] = token_idx;
            batch.n_seq_id[i] = 1;
            batch.seq_id[i][0] = 0;
            // Only request logits for the last token of the entire prompt
            batch.logits[i] = (chunk_end == n_tokens && i == chunk_tokens - 1);
        }
        
        // Decode the prompt chunk
        if (llama_decode(ctx, batch) != 0) {
#ifdef DEBUG
            NSLog(@"❌ Failed to decode prompt batch for streaming");
#endif
            llama_batch_free(batch);
            if (self.streamingDelegate) {
                [self.streamingDelegate llamaBridge:self didCompleteWithResponse:@"Error: Failed to decode prompt"];
            }
            return;
        }
        
        llama_batch_free(batch);
    }
    
    // STREAMING GENERATION LOOP - Each token sent immediately
    std::string response;
    int n_generated = 0;
    
    while (n_generated < maxTokens && !shouldStop) {
        // Get logits for next token
        float* logits = llama_get_logits_ith(ctx, -1);
        if (!logits) {
            break;
        }
        
        // Simple greedy selection for streaming speed
        int32_t vocab_size = llama_vocab_n_tokens(vocab);
        llama_token next_token = 0;
        float max_logit = -INFINITY;
        
        for (int32_t i = 0; i < vocab_size; i++) {
            if (std::isfinite(logits[i]) && logits[i] > max_logit) {
                max_logit = logits[i];
                next_token = i;
            }
        }
        
        // AUTOMATIC EOS DETECTION: Replicate Python wrapper's natural stopping behavior
        // Check for any EOG (End of Generation) tokens that indicate natural completion
        if (next_token == 128001 ||  // <|end_of_text|> - Natural completion
            next_token == 128008 ||  // <|eom_id|> - End of message
            next_token == 128009) {  // <|eot_id|> - End of turn
            break; // Respect the LLM's natural stopping point
        }
        
        // Convert token to text
        char token_str[256];
        int32_t token_len = llama_token_to_piece(vocab, next_token, token_str, sizeof(token_str), 0, false);
        
        if (token_len > 0) {
            token_str[token_len] = '\0';
            std::string token_text(token_str);
            
            // STRICT: Check for any conversation patterns that indicate fake dialogue
            if (token_text.find("User:") != std::string::npos || 
                token_text.find("user:") != std::string::npos ||
                token_text.find("Human:") != std::string::npos ||
                token_text.find("Question:") != std::string::npos ||
                token_text.find("I'm considering participating") != std::string::npos ||  // More specific patterns
                token_text.find("I've heard mixed reviews") != std::string::npos) {
                break; // Stop if LLM tries to generate fake conversations
            }
            
            response += token_text;
            
            // REAL-TIME STREAMING: Send token immediately to delegate
            NSString *tokenNS = [NSString stringWithUTF8String:token_text.c_str()];
            NSString *partialResponseNS = [NSString stringWithUTF8String:response.c_str()];
            [streamingResponse appendString:tokenNS];
            
            // Update UI immediately on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.streamingDelegate) {
                    [self.streamingDelegate llamaBridge:self didGenerateToken:tokenNS partialResponse:partialResponseNS];
                }
            });
        }
        
        // Check for end of generation
        if (next_token == llama_vocab_eos(vocab)) {
            break;
        }
        
        // Create batch for next token
        llama_batch token_batch = llama_batch_init(1, 0, 1);
        token_batch.n_tokens = 1;
        token_batch.token[0] = next_token;
        token_batch.pos[0] = n_tokens + n_generated;
        token_batch.n_seq_id[0] = 1;
        token_batch.seq_id[0][0] = 0;
        token_batch.logits[0] = true;
        
        // Decode next token
        if (llama_decode(ctx, token_batch) != 0) {
            llama_batch_free(token_batch);
            break;
        }
        
        llama_batch_free(token_batch);
        n_generated++;
    }
    
    // Send final completion
    NSString *finalResponse = [NSString stringWithUTF8String:response.c_str()];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.streamingDelegate) {
            [self.streamingDelegate llamaBridge:self didCompleteWithResponse:finalResponse];
        }
    });
}

- (void)stopGeneration {
    shouldStop = true;
}

- (void)unloadModel {
    if (ctx) {
        llama_free(ctx);
        ctx = nullptr;
    }
    if (model) {
        llama_model_free(model);
        model = nullptr;
    }
    _isModelLoaded = NO;
    _loadingProgress = 0.0;
}

- (size_t)getCurrentMemoryUsage {
    if (!model) return 0;
    return llama_model_size(model);
}

- (void)reduceMemoryFootprint {
    // Clear KV cache if function exists, otherwise skip
    // llama_kv_cache_clear(ctx);
#ifdef DEBUG
    NSLog(@"🧹 Memory footprint reduction requested");
#endif
}

- (NSDictionary *)getModelInfo {
    if (!model) {
        return @{@"error": @"Model not loaded"};
    }
    
    const struct llama_vocab* vocab = llama_model_get_vocab(model);
    
    return @{
        @"name": @"LLaMA 3.2 3B Instruct (Real Inference)",
        @"parameters": @(llama_model_n_params(model)),
        @"context_length": @(ctx_params.n_ctx),
        @"vocab_size": @(llama_vocab_n_tokens(vocab)),
        @"embedding_size": @(llama_model_n_embd(model))
    };
}

- (void)dealloc {
    [self unloadModel];
    llama_backend_free();
}

@end
