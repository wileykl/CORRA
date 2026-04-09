//
//  LlamaCppBridge.h
//  Objective-C++ bridge header for llama.cpp
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Forward declaration
@class LlamaCppBridge;

// Streaming delegate protocol for real-time token updates
@protocol LlamaCppBridgeStreamingDelegate <NSObject>
- (void)llamaBridge:(LlamaCppBridge *)bridge didGenerateToken:(NSString *)token partialResponse:(NSString *)partialResponse;
- (void)llamaBridge:(LlamaCppBridge *)bridge didCompleteWithResponse:(NSString *)finalResponse;
@end

@interface LlamaCppBridge : NSObject

@property (nonatomic, readonly) BOOL isModelLoaded;
@property (nonatomic, readonly) float loadingProgress;
@property (nonatomic, weak) id<LlamaCppBridgeStreamingDelegate> streamingDelegate;

// Initialization with configuration
- (instancetype)initWithModelPath:(NSString *)modelPath
                       contextSize:(int32_t)contextSize
                         gpuLayers:(int32_t)gpuLayers
                          useMlock:(BOOL)useMlock;

// Simpler initialization
- (instancetype)initWithModelPath:(NSString *)modelPath;

// Model operations
- (BOOL)loadModelWithError:(NSError **)error;
- (void)unloadModel;

// Configuration
- (void)setSystemPrompt:(NSString *)systemPrompt;
- (void)setContextSize:(int32_t)contextSize;

// Text generation
- (NSString *)generateResponseForPrompt:(NSString *)prompt
                               maxTokens:(int32_t)maxTokens
                             temperature:(float)temperature;

// Streaming text generation (real-time token updates via delegate)
- (void)generateStreamingResponseForPrompt:(NSString *)prompt
                                 maxTokens:(int32_t)maxTokens
                               temperature:(float)temperature;

// Memory management helpers
- (size_t)getCurrentMemoryUsage;
- (void)reduceMemoryFootprint;

@end

NS_ASSUME_NONNULL_END

