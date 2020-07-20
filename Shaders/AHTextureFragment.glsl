uniform sampler2D u_Texture;
uniform lowp vec4 u_Color;

varying lowp vec2 frag_TexCoord;

void main(void)
{
    gl_FragColor = u_Color * texture2D(u_Texture, frag_TexCoord);
}