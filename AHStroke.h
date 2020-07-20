#import <Foundation/Foundation.h>

#import "AHVertex.h"
#import "AHPathShader.h"
#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/glext.h>
#import <GLKit/GLKit.h>

@interface AHStroke : NSObject

@property (nonatomic, readonly) AHVertex *vertices;
@property (nonatomic, readonly) GLsizei vertexCount;

@property (nonatomic, readonly) NSArray *inputPoints;

@property (nonatomic, readonly) CGRect boundingRect;

@property (nonatomic, readonly) UIColor *lineColor;
@property (nonatomic, readonly) float lineOpacity;
@property (nonatomic, readonly) float lineWidth;

- (instancetype)initWithShader:(AHPathShader *)shader
                         point:(CGPoint)point
                         color:(UIColor *)color
                     lineWidth:(float)lineWidth;

- (instancetype)initWithShader:(AHPathShader *)shader
                        points:(NSArray *)points
                         color:(UIColor *)color
                     lineWidth:(float)lineWidth;

- (CGRect)appendCGPoint:(CGPoint)point;

- (CGRect)finishWithCGPoint:(CGPoint)point;

- (void)render;

@end
