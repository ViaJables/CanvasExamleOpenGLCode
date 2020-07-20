uniform highp mat4 u_ProjectionMatrix;
uniform float u_PointSize;

attribute vec4 a_Position;

void main(void)
{
    gl_PointSize = u_PointSize;
    gl_Position = u_ProjectionMatrix * a_Position;
}