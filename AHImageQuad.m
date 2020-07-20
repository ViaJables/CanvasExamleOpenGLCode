#import "AHImageQuad.h"

@interface AHImageQuad()
{
    GLuint  _texID, _vao, _vbo;
    CGSize  _imageSize;
    
    AHPathShader    *_shader;
}

@end

@implementation AHImageQuad

- (instancetype)initWithImage:(UIImage *)image
                         rect:(CGRect)rect
                       shader:(AHPathShader *)shader
{
    self = [super init];
    
    if (self)
    {
        _texID = [self createTextureWithAsset:image];
        
        glGenVertexArraysOES(1, &_vao);
        glBindVertexArrayOES(_vao);
        
        glGenBuffers(1, &_vbo);
        glBindBuffer(GL_ARRAY_BUFFER, _vbo);
        
        glVertexAttribPointer(AHTextureMapAttribPosition, 2, GL_FLOAT, GL_FALSE, sizeof(AHTextureMap), (const GLvoid *) offsetof(AHTextureMap, Position));
        glEnableVertexAttribArray(AHTextureMapAttribPosition);
        
        glVertexAttribPointer(AHTextureMapAttribTexCoord, 2, GL_FLOAT, GL_FALSE, sizeof(AHTextureMap), (const GLvoid *) offsetof(AHTextureMap, TexCoord));
        glEnableVertexAttribArray(AHTextureMapAttribTexCoord);
        
        glBindVertexArrayOES(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
        self.rect = rect;
        
        _shader = shader;
    }
    
    return self;
}

- (instancetype)initWithImageNamed:(NSString *)name
                              rect:(CGRect)rect
                            shader:(AHPathShader *)shader
{
    self = [super init];
    
    if (self)
    {
        _texID = [self createTextureWithAssetNamed:name];
        
        glGenVertexArraysOES(1, &_vao);
        glBindVertexArrayOES(_vao);
        
        glGenBuffers(1, &_vbo);
        glBindBuffer(GL_ARRAY_BUFFER, _vbo);
        
        glVertexAttribPointer(AHTextureMapAttribPosition, 2, GL_FLOAT, GL_FALSE, sizeof(AHTextureMap), (const GLvoid *) offsetof(AHTextureMap, Position));
        glEnableVertexAttribArray(AHTextureMapAttribPosition);
        
        glVertexAttribPointer(AHTextureMapAttribTexCoord, 2, GL_FLOAT, GL_FALSE, sizeof(AHTextureMap), (const GLvoid *) offsetof(AHTextureMap, TexCoord));
        glEnableVertexAttribArray(AHTextureMapAttribTexCoord);
        
        glBindVertexArrayOES(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
        self.rect = rect;
        
        _shader = shader;
    }
    
    return self;
}

- (void)setRect:(CGRect)rect
{
    if (!CGRectEqualToRect(rect, _rect))
    {
        CGFloat texAspect = _imageSize.width / _imageSize.height;
        CGFloat frameAspect = rect.size.width / rect.size.height;
        
        CGFloat texScale = (texAspect > frameAspect) ? (rect.size.height / _imageSize.height) : (rect.size.width / _imageSize.width);
        CGSize scaledSize = CGSizeApplyAffineTransform(_imageSize, CGAffineTransformMakeScale(texScale, texScale));
        CGRect texRect = CGRectMake(0, 0, scaledSize.width, scaledSize.height);
        
        CGRect intersectedRect = CGRectIntersection(texRect, rect);
        intersectedRect = UIEdgeInsetsInsetRect(intersectedRect, UIEdgeInsetsMake((texRect.size.height - rect.size.height) / 2.0, (texRect.size.width - rect.size.width) / 2.0, 0, 0));
        CGRect normalizedRect = CGRectApplyAffineTransform(intersectedRect, CGAffineTransformMakeScale(1 / texRect.size.width, 1 / texRect.size.height));
        
        AHTextureMap map[4] = {
            {{CGRectGetMinX(rect), CGRectGetMinY(rect)}, {CGRectGetMinX(normalizedRect), CGRectGetMaxY(normalizedRect)} },
            {{CGRectGetMinX(rect), CGRectGetMaxY(rect)}, {CGRectGetMinX(normalizedRect), CGRectGetMinY(normalizedRect)} },
            {{CGRectGetMaxX(rect), CGRectGetMinY(rect)}, {CGRectGetMaxX(normalizedRect), CGRectGetMaxY(normalizedRect)} },
            {{CGRectGetMaxX(rect), CGRectGetMaxY(rect)}, {CGRectGetMaxX(normalizedRect), CGRectGetMinY(normalizedRect)} }
        };
        
        glBindVertexArrayOES(_vao);
        glBindBuffer(GL_ARRAY_BUFFER, _vbo);
        
        glBufferData(GL_ARRAY_BUFFER, 4 * sizeof(AHTextureMap), map, GL_STATIC_DRAW);
        
        glBindVertexArrayOES(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
        _rect = rect;
    }
}

- (GLuint)createTextureWithAssetNamed:(NSString *)name
{
    return [self createTextureWithAsset:[UIImage imageNamed:name]];
}

- (GLuint)createTextureWithAsset:(UIImage *)imageRef
{
    CGImageRef		image;
    CGContextRef	imageContext;
    GLubyte			*imageData;
    GLint           width, height;
    GLuint          texId = 0;
    
    // First create a UIImage object from the data in a image file, and then extract the Core Graphics image
    image = imageRef.CGImage;
    
    // Get the width and height of the image
    width = (GLint)CGImageGetWidth(image);
    height = (GLint)CGImageGetHeight(image);
    
    // Make sure the image exists
    if(image)
    {
        // Allocate  memory needed for the bitmap context
        imageData = (GLubyte *) calloc(width * height * 4, sizeof(GLubyte));
        // Use  the bitmatp creation function provided by the Core Graphics framework.
        imageContext = CGBitmapContextCreate(imageData, width, height, 8, width * 4, CGImageGetColorSpace(image), (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        // After you create the context, you can draw the  image to the context.
        CGContextDrawImage(imageContext, CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), image);
        // You don't need the context at this point, so you need to release it to avoid memory leaks.
        CGContextRelease(imageContext);
        // Use OpenGL ES to generate a name for the texture.
        glGenTextures(1, &texId);
        // Bind the texture name.
        glBindTexture(GL_TEXTURE_2D, texId);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)width, (int)height, 0, GL_RGBA, GL_UNSIGNED_BYTE, imageData);
        
        // Release  the image data; it's no longer needed
        free(imageData);
    }
    
    _imageSize = CGSizeMake(width, height);
    
    return texId;
}

- (void)render
{
    glBindVertexArrayOES(_vao);
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    
    _shader.color = GLKVector4Make(1.0, 1.0, 1.0, 1.0);
    _shader.textureID = _texID;
    
    [_shader prepareToDraw];
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

- (void)dealloc
{
    if (_texID > 0)
    {
        glDeleteTextures(1, &_texID);
    }
    
    if (_vao > 0)
    {
        glDeleteVertexArraysOES(1, &_vao);
    }
    
    if (_vbo > 0)
    {
        glDeleteBuffers(1, &_vbo);
    }
}

@end
