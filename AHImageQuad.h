#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "AHVertex.h"
#import "AHPathShader.h"
#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/glext.h>
#import <GLKit/GLKit.h>

@interface AHImageQuad : NSObject

@property (assign, nonatomic) CGRect rect;

- (instancetype)initWithImage:(UIImage *)image
                         rect:(CGRect)rect
                       shader:(AHPathShader *)shader;

- (void)render;

@end
