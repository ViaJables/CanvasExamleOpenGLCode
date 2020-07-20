#import <GLKit/GLKit.h>

typedef enum
{
    AHVertexAttribPosition = 0,
} AHVertexAttributes;

typedef struct
{
    GLfloat Position[2];
} AHVertex;

typedef enum
{
    AHTextureMapAttribPosition = 0,
    AHTextureMapAttribTexCoord
} AHTextureMapAttributes;

typedef struct
{
    GLfloat Position[2];
    GLfloat TexCoord[2];
} AHTextureMap;

GLK_INLINE AHVertex
AHVertexMakeWithGLKVector2(GLKVector2 vector)
{
    AHVertex v = { vector.x, vector.y };
    return v;
}

GLK_INLINE AHVertex
AHVertexMakeWithCGPoint(CGPoint pt)
{
    AHVertex v = { pt.x, pt.y };
    return v;
}

GLK_INLINE GLKVector2
GLKVector2MakeWithVertex(AHVertex vertex)
{
    return GLKVector2Make(vertex.Position[0], vertex.Position[1]);
}

GLK_INLINE GLKVector2
GLKVector2MakeWithCGPoint(CGPoint pt)
{
    return GLKVector2Make(pt.x, pt.y);
}

CG_INLINE CGPoint
CGPointMidPoint(CGPoint pt1, CGPoint pt2)
{
    return CGPointMake((pt1.x + pt2.x) / 2.0, (pt1.y + pt2.y) / 2.0);
}

GLK_INLINE GLKVector2
GLKVector2UnitNormal(CGPoint pt1, CGPoint pt2)
{
    return GLKVector2Normalize(GLKVector2Make(pt1.y - pt2.y, pt2.x - pt1.x));
}

GLK_INLINE float
GLKVector2Angle(GLKVector2 vector)
{
    return acosf(GLKVector2DotProduct(GLKVector2Normalize(vector), GLKVector2Make(1.0, 0.0)));
}

GLK_INLINE BOOL
GLKVector2IsParallel(GLKVector2 v0, GLKVector2 v1)
{
    return (((v0.x / v1.x) == (v0.y / v1.y)) ||
            (v0.x == 0 && v1.x == 0) ||
            (v0.y == 0 && v1.y == 0));
}

GLK_INLINE GLKVector2
GLKVector2Rotate(GLKVector2 v, float angle)
{
    GLKMatrix3 rotationMatrix = GLKMatrix3MakeRotation(angle, 0, 0, 1.0);
    GLKVector3 rotatedVector3D = GLKMatrix3MultiplyVector3(rotationMatrix, GLKVector3Make(v.x, v.y, 0));
    
    return GLKVector2Make(rotatedVector3D.x, rotatedVector3D.y);
}


GLK_INLINE GLKVector2
GLKVector2RotateAboutPoint(GLKVector2 v, float angle, GLKVector2 centerPoint)
{
    return GLKVector2Add(GLKVector2Rotate(GLKVector2Subtract(v, centerPoint), angle), centerPoint);
}