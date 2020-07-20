#import "AHDrawingView.h"
#import "AHStroke+Utilities.h"
#import "AHPathShader.h"

#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <QuartzCore/QuartzCore.h>

#import "AHImageQuad.h"

#import "AHPersistentDrawing.h"
#import "AHPersistentStroke.h"

@interface AHDrawingView()
{
    AHStroke        *_activeStroke;
    AHPathShader    *_pathShader;
    AHPathShader    *_texShader;
    
    EAGLContext     *_context;
    
    BOOL            _isInitialized;
    
    NSMutableArray  *_strokes;
    
    GLuint  _viewFrameBuffer, _viewRenderBuffer;
    GLuint  _texVertexVAO, _texVertexVBO;
    GLuint  _backFrameBuffer, _backTex;
    GLuint  _scratchFrameBuffer[2], _scratchTex[2];
    GLuint  _undoFrameBuffer, _undoTex;
    
    NSInteger _counter;
    
    GLuint  _msFrameBuffer, _msColorRenderBuffer;
    
    GLint   _backingWidth, _backingHeight;
    
    CGRect  _lastUpdateRect;
    
    CGFloat _lineWidth;
    
    AHImageQuad *_imageQuad;
}

@end

@implementation AHDrawingView

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    
    if (self)
    {
        [self setupDefaults];
    }
    
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self)
    {
        [self setupDefaults];
    }
    
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    [EAGLContext setCurrentContext:_context];
    
    if (!_isInitialized)
    {
        [self setupGL];
        
        _isInitialized = YES;
    }
}

+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

#pragma mark - Setup

- (void)setupGL
{
    glGenFramebuffers(1, &_viewFrameBuffer);
    glGenRenderbuffers(1, &_viewRenderBuffer);
    
    glBindFramebuffer(GL_FRAMEBUFFER, _viewFrameBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _viewRenderBuffer);
    
    [_context renderbufferStorage:GL_RENDERBUFFER
                     fromDrawable:(id<EAGLDrawable>)self.layer];
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _viewRenderBuffer);
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        return;
    }
    
    glDisable(GL_DEPTH_TEST);
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    
    glViewport(0, 0, _backingWidth, _backingHeight);
    
    [self createTextureFBOWithHandle:&_backFrameBuffer
                       textureHandle:&_backTex
                         bufferWidth:_backingWidth
                              height:_backingHeight];
    
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    [self createTextureFBOWithHandle:&_undoFrameBuffer
                       textureHandle:&_undoTex
                         bufferWidth:_backingWidth
                              height:_backingHeight];
    
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    [self createTextureFBOWithHandle:&_scratchFrameBuffer[0]
                       textureHandle:&_scratchTex[0]
                         bufferWidth:_backingWidth
                              height:_backingHeight];
    
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    [self createTextureFBOWithHandle:&_scratchFrameBuffer[1]
                       textureHandle:&_scratchTex[1]
                         bufferWidth:_backingWidth
                              height:_backingHeight];
    
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    [self setupTextureArrayBufferWithWidth:_backingWidth
                                    height:_backingHeight];
    
    [self setupMultisampleFramebufferWithWidth:_backingWidth
                                        height:_backingHeight];
    
    _pathShader = [[AHPathShader alloc] initWithVertexShader:@"AHPathVertex.glsl"
                                              fragmentShader:@"AHPathFragment.glsl"];
    
    _texShader = [[AHPathShader alloc] initWithVertexShader:@"AHTextureVertex.glsl"
                                             fragmentShader:@"AHTextureFragment.glsl"];
    
    CGRect bounds = self.bounds;
    GLKMatrix4 ortho = GLKMatrix4MakeOrtho(0,
                                           bounds.size.width,
                                           bounds.size.height,
                                           0,
                                           -1.0,
                                           1.0);
    
    _pathShader.projectionMatrix = ortho;
    _texShader.projectionMatrix = GLKMatrix4Scale(ortho, 1.0 / self.contentScaleFactor , 1.0 / self.contentScaleFactor, 1.0);
    
    _imageQuad = [[AHImageQuad alloc] initWithImage:[self generateGrid]
                                               rect:CGRectApplyAffineTransform(self.bounds, CGAffineTransformMakeScale(self.contentScaleFactor, self.contentScaleFactor))
                                             shader:_texShader];
    
    glBindFramebuffer(GL_FRAMEBUFFER, _viewFrameBuffer);
    
    [self drawGLRect:self.bounds];
}

- (UIImage *)generateGrid
{
    // begin a graphics context of sufficient size
    UIGraphicsBeginImageContext(self.bounds.size);
    
    // get the context for CoreGraphics
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    // set stroking color and draw circle
    CGContextSetStrokeColorWithColor(ctx, [[UIColor colorWithRed:0 green:0 blue:1 alpha:0.1] CGColor]);
    
    CGContextSetLineWidth(ctx, 0.25);
    
    for(NSInteger x = 15; x<self.frame.size.width; x+=15)
    {
        CGContextMoveToPoint(ctx, x, 0);
        CGContextAddLineToPoint(ctx, x, self.bounds.size.height);
        CGContextStrokePath(ctx);
    }
    
    for(NSInteger y = 15; y<self.bounds.size.height; y+=15)
    {
        CGContextMoveToPoint(ctx, 0, y);
        CGContextAddLineToPoint(ctx, self.bounds.size.width, y);
        CGContextStrokePath(ctx);
    }
    
    // make image out of bitmap context
    UIImage *gridImage = UIGraphicsGetImageFromCurrentImageContext();
    
    // free the context
    UIGraphicsEndImageContext();
    
    return gridImage;
}

- (void)setupDefaults
{
    self.contentScaleFactor = [[UIScreen mainScreen] scale];
    
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
    eaglLayer.opaque = YES;
    eaglLayer.drawableProperties = @
    {
        kEAGLDrawablePropertyRetainedBacking : @NO,
        kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8
    };
    
    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    _strokes = [NSMutableArray array];
    self.backgroundColor = [UIColor clearColor];
    
    self.lineColor = [UIColor colorWithRed:0
                                     green:0
                                      blue:0
                                     alpha:1.0];
    self.lineWidth = 6.0;
    self.lineOpacity = 1.0;
    self.multipleTouchEnabled = NO;
}

- (void)createTextureFBOWithHandle:(GLuint *)fboHandle
                     textureHandle:(GLuint *)texHandle
                       bufferWidth:(GLint)width
                            height:(GLint)height
{
    if (*fboHandle != 0)
    {
        glDeleteTextures(1, texHandle);
        glDeleteFramebuffers(1, fboHandle);
    }
    
    glGenFramebuffers(1, fboHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, *fboHandle);
    
    [self setupTexture:texHandle
             withWidth:width
                height:height];
    
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    
    if (status != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"Failed to make complete framebuffer: %x", status);
    }
}

- (void)setupTexture:(GLuint *)textureHandle
           withWidth:(GLint)width
              height:(GLint)height
{
    glGenTextures(1, textureHandle);
    glBindTexture(GL_TEXTURE_2D, *textureHandle);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, *textureHandle, 0);
    
}

- (void)setupMultisampleFramebufferWithWidth:(GLint)width
                                      height:(GLint)height
{
    if (_msFrameBuffer != 0)
    {
        glDeleteRenderbuffers(1, &_msColorRenderBuffer);
        glDeleteFramebuffers(1, &_msFrameBuffer);
    }
    
    glGenFramebuffers(1, &_msFrameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _msFrameBuffer);
    
    glGenRenderbuffers(1, &_msColorRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _msColorRenderBuffer);
    glRenderbufferStorageMultisampleAPPLE(GL_RENDERBUFFER, 4, GL_RGBA8_OES, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _msColorRenderBuffer);
    
    GLint max_rb_size, max_samples_apple;
    glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE, &max_rb_size);
    glGetIntegerv(GL_MAX_SAMPLES_APPLE, &max_samples_apple);
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"Failed to make complete framebuffer object: %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
    
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindRenderbuffer(GL_RENDERBUFFER, 0);
}

- (void)setupTextureArrayBufferWithWidth:(GLint)width
                                  height:(GLint)height
{
    glGenVertexArraysOES(1, &_texVertexVAO);
    glBindVertexArrayOES(_texVertexVAO);
    
    glGenBuffers(1, &_texVertexVBO);
    glBindBuffer(GL_ARRAY_BUFFER, _texVertexVBO);
    
    glEnableVertexAttribArray(AHTextureMapAttribPosition);
    glVertexAttribPointer(AHTextureMapAttribPosition, 2, GL_FLOAT, GL_FALSE, sizeof(AHTextureMap), (const GLvoid *) offsetof(AHTextureMap, Position));
    
    glEnableVertexAttribArray(AHTextureMapAttribTexCoord);
    glVertexAttribPointer(AHTextureMapAttribTexCoord, 2, GL_FLOAT, GL_FALSE, sizeof(AHTextureMap), (const GLvoid *) offsetof(AHTextureMap, TexCoord));
    
    AHTextureMap map[4] = {
        {{0.0, 0.0}, {0.0, 1.0}},
        {{(GLfloat) width, 0.0}, {1.0, 1.0}},
        {{0.0, (GLfloat) height}, {0.0, 0.0}},
        {{(GLfloat)width, (GLfloat)height}, {1.0, 0.0}}
    };
    
    glBufferData(GL_ARRAY_BUFFER, 4 * sizeof(AHTextureMap), map, GL_DYNAMIC_DRAW);
    
    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

#pragma mark - Draw

- (void)drawGLRect:(CGRect)rect
{
    glBindFramebuffer(GL_FRAMEBUFFER, _viewFrameBuffer);
    
    glClearColor(1.0, 1.0, 1.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    [_imageQuad render];
    
    [self drawRect:self.bounds
         ofTexture:_backTex
       withOpacity:1.0];
    
    if (_activeStroke)
    {
        [self drawStroke:_activeStroke
                 inFrame:rect
           ofFrameBuffer:_viewFrameBuffer];
    }
    
    glBindRenderbuffer(GL_RENDERBUFFER, _viewRenderBuffer);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

#pragma mark - Public API

- (BOOL)canUndo
{
    return _strokes.count > 0;
}

- (void)undo
{
    if (_strokes.count > 0)
    {
        glBindFramebuffer(GL_FRAMEBUFFER, _backFrameBuffer);
        glClearColor(0.0, 0.0, 0.0, 0.0);
        glClear(GL_COLOR_BUFFER_BIT);
        
        [self drawRect:self.bounds
             ofTexture:_undoTex
           withOpacity:1.0];
        
        [_strokes removeLastObject];
        
        for (AHStroke *thisStroke in _strokes)
        {
            [self drawStroke:thisStroke
                     inFrame:thisStroke.boundingRect
               ofFrameBuffer:_backFrameBuffer];
        }
        
        [self drawGLRect:self.bounds];
        
        glBindFramebuffer(GL_FRAMEBUFFER, _msFrameBuffer);
        glClearColor(0.0, 0.0, 0.0, 0.0);
        glClear(GL_COLOR_BUFFER_BIT);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
}

- (void)clear
{
    glBindFramebuffer(GL_FRAMEBUFFER, _backFrameBuffer);
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    [self drawGLRect:self.bounds];
}

- (UIImage *)imageWithScale:(CGFloat)scale
{
    return [self imageWithScale:scale
                backgroundColor:[UIColor whiteColor]];
}

- (UIImage *)imageWithScale:(CGFloat)scale
            backgroundColor:(UIColor *)backgroundColor
{
    NSInteger dataLength = _backingWidth * _backingHeight * 4;
    GLubyte *imageBuffer = (GLubyte *)malloc(dataLength);
    
    glBindFramebuffer(GL_FRAMEBUFFER, _backFrameBuffer);
    
    glReadPixels(0, 0, _backingWidth, _backingHeight, GL_RGBA, GL_UNSIGNED_BYTE, imageBuffer);
    
    GLubyte *transposedBuffer = (GLubyte *)malloc(dataLength);
    
    for (int y = 0; y < _backingHeight; y ++)
    {
        memcpy(transposedBuffer + (_backingHeight - 1 - y) * _backingWidth * 4, imageBuffer + (y * 4 * _backingWidth), _backingWidth * 4);
    }
    
    free(imageBuffer);
    
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, transposedBuffer, dataLength, NULL);
    int bitsPerComponent = 8;
    int bitsPerPixel = 32;
    int bytesPerRow = 4 * _backingWidth;
    
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = (CGBitmapInfo) kCGBitmapAlphaInfoMask & kCGImageAlphaPremultipliedLast;
    CGImageRef imageRef = CGImageCreate(
                                        _backingWidth,
                                        _backingHeight,
                                        bitsPerComponent,
                                        bitsPerPixel,
                                        bytesPerRow,
                                        colorSpaceRef,
                                        bitmapInfo,
                                        provider,
                                        NULL,
                                        NO,
                                        kCGRenderingIntentDefault
                                        );
    
    CGRect newRect = CGRectApplyAffineTransform(self.bounds, CGAffineTransformMakeScale(scale, scale));
    
    CGContextRef bitmap = CGBitmapContextCreate(
                                                NULL,
                                                newRect.size.width,
                                                newRect.size.height,
                                                8, /* bits per channel */
                                                (newRect.size.width * 4), /* 4 channels per pixel * numPixels/row */
                                                colorSpaceRef,
                                                bitmapInfo
                                                );
    
    // Set the quality level to use when rescaling
    CGContextSetInterpolationQuality(bitmap, kCGInterpolationHigh);
    CGContextSetFillColorWithColor(bitmap, [[UIColor whiteColor] CGColor]);
    CGContextFillRect(bitmap, newRect);
    
    // Draw into the context; this scales the image
    CGContextDrawImage(bitmap, newRect, imageRef);
    
    // Get the resized image from the context and a UIImage
    CGImageRef newImageRef = CGBitmapContextCreateImage(bitmap);
    UIImage *newImage = [UIImage imageWithCGImage:newImageRef
                                            scale:1.0
                                      orientation:UIImageOrientationUp];
    
    // Clean up
    CGContextRelease(bitmap);
    CGImageRelease(newImageRef);
    
    free(transposedBuffer);
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpaceRef);
    
    return newImage;
}

- (void)loadPersistentDrawing:(AHPersistentDrawing *)persistentDrawing
                 onCompletion:(void (^)(void))completion
{
    self.userInteractionEnabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^
                   {
                       [EAGLContext setCurrentContext:_context];
                       
                       for (AHPersistentStroke *thisPersistentStroke in persistentDrawing.actions)
                       {
                           AHStroke *thisStroke = [AHStroke strokeFromPersistentStroke:thisPersistentStroke
                                                                            withShader:_pathShader];
                           
                           [_strokes addObject:thisStroke];
                           
                           [self drawStroke:thisStroke
                                    inFrame:self.bounds
                              ofFrameBuffer:_backFrameBuffer];
                           
                           if (_strokes.count > 20)
                           {
                               [self drawStroke:_strokes.firstObject
                                        inFrame:self.bounds
                                  ofFrameBuffer:_undoFrameBuffer];
                               
                               [_strokes removeObjectAtIndex:0];
                           }
                       }
                       
                       glBindFramebuffer(GL_FRAMEBUFFER, _msFrameBuffer);
                       glClearColor(0.0, 0.0, 0.0, 0.0);
                       glClear(GL_COLOR_BUFFER_BIT);
                       glBindFramebuffer(GL_FRAMEBUFFER, 0);
                       
                       [self drawGLRect:self.bounds];
                       
                       dispatch_async(dispatch_get_main_queue(), ^
                                      {
                                          if (completion)
                                          {
                                              completion();
                                          }
                                          
                                          self.userInteractionEnabled = YES;
                                      });
                   });
}

#pragma mark - Touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UIColor *color = [self.lineColor colorWithAlphaComponent:self.lineOpacity];
    
    CGPoint pt = [self pointFromTouches:touches];
    
    _activeStroke = [[AHStroke alloc] initWithShader:_pathShader
                                               point:pt
                                               color:color
                                           lineWidth:self.lineWidth];
    [_strokes addObject:_activeStroke];
    
    _lastUpdateRect = CGRectInset(CGRectMake(pt.x, pt.y, 0, 0), -self.lineWidth / 2.0, -self.lineWidth / 2.0);
    
    [self drawGLRect:_lastUpdateRect];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGRect updateRect = [_activeStroke appendCGPoint:[self pointFromTouches:touches]];
    CGRect thisUpdateRect = CGRectUnion(updateRect, _lastUpdateRect);
    _lastUpdateRect = updateRect;
    
    [self drawGLRect:thisUpdateRect];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGRect updateRect = [_activeStroke finishWithCGPoint:[self pointFromTouches:touches]];
    CGRect thisUpdateRect = CGRectUnion(updateRect, _lastUpdateRect);
    _lastUpdateRect = updateRect;
    
    [self drawStroke:_activeStroke
             inFrame:thisUpdateRect
       ofFrameBuffer:_backFrameBuffer];
    
    glBindFramebuffer(GL_FRAMEBUFFER, _msFrameBuffer);
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    
    if (_strokes.count > 20)
    {
        [self drawStroke:_strokes.firstObject
                 inFrame:self.bounds
           ofFrameBuffer:_undoFrameBuffer];
        
        [_strokes removeObjectAtIndex:0];
    }
    
    _activeStroke = nil;
    [self drawGLRect:self.bounds];
    
    if (self.drawingDelegate && [self.drawingDelegate respondsToSelector:@selector(drawingView:didDrawStroke:)])
    {
        [self.drawingDelegate drawingView:self
                            didDrawStroke:_strokes.lastObject];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self touchesEnded:touches withEvent:event];
}

#pragma mark - Helpers

- (CGPoint)pointFromTouches:(NSSet *)touches
{
    UITouch *touch = [touches anyObject];
    CGPoint pt = [touch locationInView:self];
    
    return pt;
}

- (void)drawStroke:(AHStroke *)stroke
           inFrame:(CGRect)frame
     ofFrameBuffer:(GLuint)frameBuffer
{
    [self multisampleRender:^{ [stroke render]; }
            intoFramebuffer:_scratchFrameBuffer[_counter]];
    
    glBindFramebuffer(GL_FRAMEBUFFER, frameBuffer);
    
    [self drawRect:stroke.boundingRect
         ofTexture:_scratchTex[_counter]
       withOpacity:stroke.lineOpacity];
    
    _counter = (_counter + 1) % 2;
}

- (void)drawRect:(CGRect)rect
       ofTexture:(GLuint)tex
     withOpacity:(CGFloat)opacity
{
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    
    [self setScissorRect:rect];
    glEnable(GL_SCISSOR_TEST);
    
    _texShader.color = GLKVector4Make(opacity, opacity, opacity, opacity);
    _texShader.textureID = tex;
    
    [_texShader prepareToDraw];
    
    glBindVertexArrayOES(_texVertexVAO);
    glBindBuffer(GL_ARRAY_BUFFER, _texVertexVBO);
    
    [self bufferTexCoordsForRect:rect];
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_BLEND);
}

- (void)multisampleRender:(void(^)(void))renderBlock
          intoFramebuffer:(GLuint)frameBuffer
{
    NSParameterAssert(renderBlock);
    
    glBindFramebuffer(GL_FRAMEBUFFER, _msFrameBuffer);
    
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    renderBlock();
    
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER_APPLE, frameBuffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER_APPLE, _msFrameBuffer);
    glResolveMultisampleFramebufferAPPLE();
    
    const GLenum discards[] = { GL_COLOR_ATTACHMENT0 };
    glDiscardFramebufferEXT(GL_READ_FRAMEBUFFER_APPLE, 1, discards);
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

- (void)bufferTexCoordsForRect:(CGRect)rect
{
    AHTextureMap textureMaps[4] =
    {
        [self textureMapForPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect))
                          inRect:self.bounds],
        [self textureMapForPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect))
                          inRect:self.bounds],
        [self textureMapForPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect))
                          inRect:self.bounds],
        [self textureMapForPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect))
                          inRect:self.bounds]
    };
    
    glBufferData(GL_ARRAY_BUFFER, 4 * sizeof(AHTextureMap), textureMaps, GL_DYNAMIC_DRAW);
}

- (AHTextureMap)textureMapForPoint:(CGPoint)point
                            inRect:(CGRect)outerRect
{
    CGPoint pt = CGPointApplyAffineTransform(point, CGAffineTransformMakeScale(self.contentScaleFactor, self.contentScaleFactor));
    
    return (AHTextureMap) { { pt.x, pt.y }, { point.x / outerRect.size.width, 1.0 - (point.y / outerRect.size.height) } };
}

- (void)setScissorRect:(CGRect)rect
{
    CGFloat scale = self.contentScaleFactor;
    CGAffineTransform t = CGAffineTransformTranslate(CGAffineTransformMakeScale(scale, -scale), 0.0, -self.bounds.size.height);
    CGRect scissorRect = CGRectApplyAffineTransform(rect, t);
    
    glScissor(scissorRect.origin.x, scissorRect.origin.y, scissorRect.size.width, scissorRect.size.height);
}

#pragma mark - Dealloc

- (void)dealloc
{
    if (_viewFrameBuffer != 0)
    {
        glDeleteFramebuffers(1, &_viewFrameBuffer);
        glDeleteRenderbuffers(1, &_viewRenderBuffer);
    }
    
    if (_backFrameBuffer != 0)
    {
        glDeleteFramebuffers(1, &_backFrameBuffer);
        glDeleteTextures(1, &_backTex);
    }
    
    if (_scratchFrameBuffer != 0)
    {
        glDeleteFramebuffers(2, _scratchFrameBuffer);
        glDeleteTextures(2, _scratchTex);
    }
    
    if (_undoFrameBuffer != 0)
    {
        glDeleteFramebuffers(1, &_undoFrameBuffer);
        glDeleteTextures(1, &_undoTex);
    }
    
    if (_msFrameBuffer != 0)
    {
        glDeleteFramebuffers(1, &_msFrameBuffer);
        glDeleteRenderbuffers(1, &_msColorRenderBuffer);
    }
    
    if (_texVertexVAO != 0)
    {
        glDeleteVertexArraysOES(1, &_texVertexVAO);
        glDeleteBuffers(1, &_texVertexVBO);
    }
}

@end
