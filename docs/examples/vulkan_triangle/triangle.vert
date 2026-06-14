#version 450

// Spinning triangle, no vertex buffers: positions/colours are hardcoded and
// indexed by gl_VertexIndex. The rotation angle arrives as a push constant.
layout(push_constant) uniform PushConstants {
    float angle;
} pc;

layout(location = 0) out vec3 vColor;

void main()
{
    vec2 positions[3] = vec2[](
        vec2( 0.0, -0.6),
        vec2( 0.6,  0.5),
        vec2(-0.6,  0.5)
    );
    vec3 colors[3] = vec3[](
        vec3(1.0, 0.0, 0.0),
        vec3(0.0, 1.0, 0.0),
        vec3(0.0, 0.0, 1.0)
    );

    float s = sin(pc.angle);
    float c = cos(pc.angle);
    mat2 rot = mat2(c, -s, s, c);

    gl_Position = vec4(rot * positions[gl_VertexIndex], 0.0, 1.0);
    vColor = colors[gl_VertexIndex];
}
