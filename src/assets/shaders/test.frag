#version 330

in vec2 vUV;
out vec4 FragColor;

uniform sampler2D u_texture; // input texture to blur
uniform vec2 u_resolution;    // resolution of the texture

// 1D Gaussian weights (normalized)
float gaussianWeight(int x, float sigma) {
    return exp(-float(x*x)/(2.0*sigma*sigma));
}

void main()
{
    vec2 texel = 1.0 / u_resolution; // size of one pixel
    float sigma = 3 / 2.0;
    
    vec3 color = vec3(0.0);
    float weightSum = 0.0;

    // horizontal blur
    for(int i = -4; i <= 4; i++) {
        float w = gaussianWeight(i, sigma);
        vec2 offset = vec2(float(i), 0.0) * texel;
        color += texture(u_texture, vUV + offset).rgb * w;
        weightSum += w;
    }
    color /= weightSum;

    // optional: vertical blur
    vec3 finalColor = vec3(0.0);
    weightSum = 0.0;
    for(int i = -4; i <= 4; i++) {
        float w = gaussianWeight(i, sigma);
        vec2 offset = vec2(0.0, float(i)) * texel;
        finalColor += texture(u_texture, vUV + offset).rgb * w;
        weightSum += w;
    }
    finalColor /= weightSum;

    FragColor = vec4(finalColor, 1.0);
}