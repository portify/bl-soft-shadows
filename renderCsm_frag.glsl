#version 120
#extension GL_EXT_texture_array : require
#extension GL_EXT_texture_array : enable

// Configuration: For the adventurous!
// This is blending. Shadows are rendered to separate layers based on distance.
// This may cause shadows to suddenly change appearance. Use this to change
// how long a distance they will "fade" between the two versions over.
float blendAlpha = 0.75f; // bl default is 0.9f
float blendBeta = 1.0f - blendAlpha;

// These values are very important. If they're too low, you will see weird
// patterns and waves everywhere. If they're too high, shadows will be
// disconnected from their objects. They need to be adjusted carefully.
// These are set specifically for Max quality with max drawing distance.
// You'll need to change them based on your shader quality (and if you changed
// the Poisson disk below.. probably).
const float fudgeFactor1 = 0.1f;
const float fudgeFactor2 = 0.25f;
const float fudgeFactor3 = 0.7f;
const float fudgeFactor4 = 2.66f;

// How soft should the shadows be? (how far out does the edge go)
// Change this or the magic numbers below to improve your "softness" quality
float sampleDistance = 1.0f / 700.0f;

// Magic numbers below
int poissonDiskCount = 24;
vec2 poissonDisk[24] = vec2[](
  vec2(0.01020043f, 0.3103616f),
  vec2(-0.4121873f, -0.1701329f),
  vec2(0.4333374f, 0.6148015f),
  vec2(0.1092096f, -0.2437763f),
  vec2(0.6641068f, -0.1210794f),
  vec2(-0.1726627f, 0.8724736f),
  vec2(-0.8549297f, 0.2836411f),
  vec2(0.5146544f, -0.6802685f),
  vec2(0.04769185f, -0.879628f),
  vec2(-0.9373617f, -0.2187589f),
  vec2(-0.69226f, -0.6652822f),
  vec2(0.9230682f, 0.3181772f),
  // these points might be bad:
  vec2(-0.1565961f, 0.8773971f),
  vec2(-0.5258075f, 0.3916658f),
  vec2(0.515902f, 0.3077986f),
  vec2(-0.006838934f, 0.2577735f),
  vec2(-0.9315282f, -0.04518054f),
  vec2(-0.3417063f, -0.1195169f),
  vec2(-0.3221133f, -0.8118886f),
  vec2(0.425082f, -0.3786222f),
  vec2(0.3917231f, 0.9194779f),
  vec2(0.8819267f, -0.1306234f),
  vec2(-0.7906089f, -0.5639677f),
  vec2(0.2073919f, -0.9611396f)
);

// This has way too much acne
// int poissonDiskCount = 35;
// vec2 poissonDisk[35] = vec2[](
//   vec2(-0.05151585f, 0.3436534f),
//   vec2(0.3648908f, 0.2827295f),
//   vec2(-0.2478754f, 0.186921f),
//   vec2(0.1171809f, 0.1482293f),
//   vec2(-0.1496224f, 0.6990415f),
//   vec2(-0.456594f, 0.378567f),
//   vec2(-0.4242465f, -0.001935145f),
//   vec2(-0.1889321f, -0.2015685f),
//   vec2(0.1480272f, 0.6432338f),
//   vec2(-0.5046303f, 0.8245607f),
//   vec2(0.001617888f, 0.9789896f),
//   vec2(-0.6228038f, 0.5963655f),
//   vec2(0.4185582f, 0.7959766f),
//   vec2(0.06965782f, -0.1184023f),
//   vec2(-0.8310863f, 0.2197417f),
//   vec2(-0.869589f, 0.4893173f),
//   vec2(-0.6366982f, -0.357598f),
//   vec2(-0.2509329f, -0.5531961f),
//   vec2(-0.03994134f, -0.4170877f),
//   vec2(-0.675245f, -0.0009701257f),
//   vec2(0.3373009f, -0.4531572f),
//   vec2(0.3022793f, -0.02336982f),
//   vec2(0.6078352f, 0.5235748f),
//   vec2(-0.9277961f, -0.05385896f),
//   vec2(0.3847639f, -0.7718652f),
//   vec2(0.5278201f, -0.168486f),
//   vec2(0.1269102f, -0.8461399f),
//   vec2(0.7260014f, -0.4588331f),
//   vec2(-0.8775687f, -0.450681f),
//   vec2(-0.574103f, -0.7766181f),
//   vec2(0.6930821f, 0.2592674f),
//   vec2(-0.3360346f, -0.8594083f),
//   vec2(-0.2591985f, 0.9300818f),
//   vec2(0.939391f, -0.2374034f),
//   vec2(0.8332635f, 0.01952092f)
// );

// Varying.
varying vec4 vPos;
varying vec3 worldNormal;
varying vec3 worldPos;

// Global directional light uniforms.
uniform vec4 dirLightDir;
uniform vec4 dirLightColor;
uniform vec4 dirLightAmbient;
uniform vec4 dirShadowColor;

// Misc uniforms.
uniform vec3 camPos;
uniform mat4 obj2World;
uniform mat4 world2Cam;

uniform int isParticle;
uniform int doColorMultiply;
uniform int glow;

uniform sampler2DArray stex;
uniform sampler2D tex;

// Surface calculations, including specular power.
varying vec2 texCoord;
vec4 viewDelta;
float specular;
float NdotL;
vec3 reflectVec;

void calculateSurface(vec4 color, inout vec4 albedo)
{
   viewDelta.xyz = worldPos - camPos;
   viewDelta.w   = length(viewDelta.xyz);
   viewDelta.xyz = -normalize(viewDelta.xyz);

   vec4 texAlbedo = texture2D(tex, texCoord);
   albedo.rgb = mix(color.rgb, texAlbedo.rgb, texAlbedo.a);

   if(doColorMultiply == 1)
      albedo *= gl_Color;

   albedo.a = color.a;

   NdotL = max(dot(worldNormal, dirLightDir.xyz), 0.0f);
   reflectVec = normalize(reflect(-dirLightDir.xyz, worldNormal));
   specular = pow(max(dot(reflectVec, viewDelta.xyz), 0.0f), 12.0f) * length(texAlbedo.rgb);

   //albedo.rgb = normalize(viewDelta.xyz);
}

// Fogging.
uniform vec4 fogBaseColor;
uniform vec4 fogConsts;
uniform sampler2D fogTex;
varying vec2 fogCoords;
void applyFog(inout vec4 albedo)
{
   // Calculate fog.
   vec4 fogColor = texture2D(fogTex, fogCoords) * fogBaseColor;

   // Blend it.
   albedo = mix(albedo, fogColor, fogColor.a);
}

// Shadowing
uniform vec4 far_d;
uniform vec2 texSize; // x - size, y - 1/size
uniform vec4 zScale;
uniform int shadowSplitCount;
void calculateShadowCoords(inout vec4 shadow_coordA, inout vec4 shadow_coordB, out float blend)
{
   int index = 3;
   float fudgeFactorA = 0.0f;
   float fudgeFactorB = 0.0f;
   fudgeFactorA = fudgeFactor4 / zScale.w;
   fudgeFactorB = fudgeFactor4 / zScale.w;
   blend = 0.0f;

   // find the appropriate depth map to look up in based on the depth of this fragment
   if(vPos.y < far_d.x)
   {
      index = 0;
      if(shadowSplitCount > 1)
         blend = clamp( (vPos.y - (far_d.x * blendAlpha)) / (far_d.x * blendBeta), 0.0f, 1.0f);
      fudgeFactorA = fudgeFactor1 / zScale.x;
      fudgeFactorB = fudgeFactor2 / zScale.y;
   }
   else if(vPos.y < far_d.y)
   {
      index = 1;
      if(shadowSplitCount > 2)
         blend = clamp( (vPos.y - (far_d.y * blendAlpha)) / (far_d.x * blendBeta), 0.0f, 1.0f);
      fudgeFactorA = fudgeFactor2 / zScale.y;
      fudgeFactorB = fudgeFactor3 / zScale.z;
   }
   else if(vPos.y < far_d.z)
   {
      index = 2;
      if(shadowSplitCount > 3)
         blend = clamp( (vPos.y - (far_d.z * blendAlpha)) / (far_d.x * blendBeta), 0.0f, 1.0f);
      fudgeFactorA = fudgeFactor3 / zScale.z;
      fudgeFactorB = fudgeFactor4 / zScale.w;
   }

   // transform this fragment's position from view space to scaled light clip space
   // such that the xy coordinates are in [0;1]
   // note there is no need to divide by w for orthogonal light sources
   shadow_coordA   = gl_TextureMatrix[index]*vPos;
   shadow_coordA.w = shadow_coordA.z - fudgeFactorA; // Figure the input coordinate for PCF sampling if appropriate.
   shadow_coordA.z = float(index);                   // Encode the layer to sample.

   //don't have to set second shadow coord if we're not blending
   if(blend > 0.0f)
   {
      shadow_coordB   = gl_TextureMatrix[index + 1]*vPos;
      shadow_coordB.w = shadow_coordB.z - fudgeFactorB;
      shadow_coordB.z = float(index + 1);
   }
}

// Point lighting
uniform vec4     pointLightPos0;
uniform vec4   pointLightColor0;
uniform float pointLightRadius0;

uniform vec4     pointLightPos1;
uniform vec4   pointLightColor1;
uniform float pointLightRadius1;

uniform vec4     pointLightPos2;
uniform vec4   pointLightColor2;
uniform float pointLightRadius2;

uniform vec4     pointLightPos3;
uniform vec4   pointLightColor3;
uniform float pointLightRadius3;

uniform vec4     pointLightPos4;
uniform vec4   pointLightColor4;
uniform float pointLightRadius4;

uniform vec4     pointLightPos5;
uniform vec4   pointLightColor5;
uniform float pointLightRadius5;

uniform vec4     pointLightPos6;
uniform vec4   pointLightColor6;
uniform float pointLightRadius6;

uniform vec4     pointLightPos7;
uniform vec4   pointLightColor7;
uniform float pointLightRadius7;

vec4 accumulatePointLights()
{
   vec4 pointLightTotal = vec4(0.0f, 0.0f, 0.0f, 0.0f);
   vec3 lightDelta = vec3(0.0f, 0.0f, 0.0f);
   float lightDot = 0.0f;
   float ratio = 0.0f;

   // Calculate effects of the 8 point lights.

   lightDelta = worldPos.xyz - pointLightPos0.xyz;
   lightDot = max(dot(-normalize(lightDelta), worldNormal), 0.0f);
   ratio = 1.0f - (length(lightDelta) / pointLightRadius0);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * lightDot * pointLightColor0.xyz;

   lightDelta = worldPos.xyz - pointLightPos1.xyz;
   lightDot = max(dot(-normalize(lightDelta), worldNormal), 0.0f);
   ratio = 1.0f - (length(lightDelta) / pointLightRadius1);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * lightDot * pointLightColor1.xyz;

   lightDelta = worldPos.xyz - pointLightPos2.xyz;
   lightDot = max(dot(-normalize(lightDelta), worldNormal), 0.0f);
   ratio = 1.0f - (length(lightDelta) / pointLightRadius2);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * lightDot * pointLightColor2.xyz;

   lightDelta = worldPos.xyz - pointLightPos3.xyz;
   lightDot = max(dot(-normalize(lightDelta), worldNormal), 0.0f);
   ratio = 1.0f - (length(lightDelta) / pointLightRadius3);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * lightDot * pointLightColor3.xyz;

   lightDelta = worldPos.xyz - pointLightPos4.xyz;
   lightDot = max(dot(-normalize(lightDelta), worldNormal), 0.0f);
   ratio = 1.0f - (length(lightDelta) / pointLightRadius4);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * lightDot * pointLightColor4.xyz;

   lightDelta = worldPos.xyz - pointLightPos5.xyz;
   lightDot = max(dot(-normalize(lightDelta), worldNormal), 0.0f);
   ratio = 1.0f - (length(lightDelta) / pointLightRadius5);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * lightDot * pointLightColor5.xyz;

   lightDelta = worldPos.xyz - pointLightPos6.xyz;
   lightDot = max(dot(-normalize(lightDelta), worldNormal), 0.0f);
   ratio = 1.0f - (length(lightDelta) / pointLightRadius6);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * lightDot * pointLightColor6.xyz;

   lightDelta = worldPos.xyz - pointLightPos7.xyz;
   lightDot = max(dot(-normalize(lightDelta), worldNormal), 0.0f);
   ratio = 1.0f - (length(lightDelta) / pointLightRadius7);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * lightDot * pointLightColor7.xyz;

   return pointLightTotal;
}

vec4 accumulateParticlePointLights()
{
   vec4 pointLightTotal = vec4(0.0f, 0.0f, 0.0f, 0.0f);
   vec3 lightDelta = vec3(0.0f, 0.0f, 0.0f);
   float ratio = 0.0f;

   // Calculate effects of the 8 point lights.

   lightDelta = worldPos.xyz - pointLightPos0.xyz;
   ratio = 1.0f - (length(lightDelta) / pointLightRadius0);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * pointLightColor0.xyz;

   lightDelta = worldPos.xyz - pointLightPos1.xyz;
   ratio = 1.0f - (length(lightDelta) / pointLightRadius1);
   ratio = ratio * ratio * ratio * 0.4f;
   ratio = max(ratio, 0.0f);
   pointLightTotal.xyz += ratio * pointLightColor1.xyz;

   return pointLightTotal;
}

// Combine specular and direct lighting terms.
// note: if we make combinedColor "out" only, it throws a potentially uninitialized value warning, so we've made it inout
void applyLighting(inout vec4 combinedColor, vec4 albedo, float occlusionFactor)
{
   //large normal means glowing object
   if(glow == 1 || (worldNormal.x + worldNormal.y + worldNormal.z) > 2.0f)
   {
      combinedColor = albedo;
      return;
   }

   vec4 dirLightSpecular = occlusionFactor * specular * dirLightColor;
   dirLightSpecular *= 0.5f; //arbitrary adjustment
   vec4 dirLightDirect = ((NdotL * dirLightColor) * occlusionFactor) + (dirLightAmbient * occlusionFactor) + (dirShadowColor * (1.0f - occlusionFactor));

   if(NdotL <= 0.04f)
   {
      dirLightDirect = dirShadowColor;
      dirLightSpecular = vec4(0.0f, 0.0f, 0.0f, 0.0f);
   }
   else if(NdotL <= 0.1)
   {
      float val = (NdotL - 0.04f) / (0.1f - 0.04f);
      dirLightDirect = (dirLightDirect * val) + (dirShadowColor * (1.0f - val));
      dirLightSpecular = dirLightSpecular * val;
   }

   dirLightDirect += accumulatePointLights();

   dirLightSpecular.a = length(dirLightSpecular.rgb);
   dirLightDirect.a *= min(occlusionFactor + 0.75f, 1.0f);
   combinedColor.rgb = dirLightDirect.rgb * albedo.rgb;
   combinedColor.a = albedo.a;
   combinedColor += dirLightSpecular;
}

float poissonSample(vec4 shadow_coord, float spread)
{
  int hit = 0;

  for (int i = 0; i < poissonDiskCount; i++) {
    float dist = texture2DArray(stex, vec3(shadow_coord.xy + poissonDisk[i] * spread, shadow_coord.z)).x;

    if (dist - shadow_coord.w > 0.0f)
      hit++;
  }

  return float(hit) / poissonDiskCount;
}

float shadowCoef()
{
  vec4 shadow_coordA = vec4(0.0f, 0.0f, 0.0f, 0.0f);
  vec4 shadow_coordB = vec4(0.0f, 0.0f, 0.0f, 0.0f);
  float blend = 0.0f;

	calculateShadowCoords(shadow_coordA, shadow_coordB, blend);

  float sampleA = poissonSample(shadow_coordA, sampleDistance);

  if (blend > 0.0f)
  {
    float sampleB = poissonSample(shadow_coordB, sampleDistance);
    return clamp((sampleB * blend) + (sampleA * (1.0f - blend)), 0.0f, 1.0f);
  }

  return sampleA;
}

void main()
{
   vec4 albedo = vec4(0.0f, 0.0f, 0.0f, 0.0f);
   calculateSurface(gl_Color, albedo);

   float occlusionFactor = 0.0f;
   if(NdotL > -0.01f)
   {
      if(shadowSplitCount <= 0)
         occlusionFactor = 1.0f;
      else
         occlusionFactor = shadowCoef();
   }

   // Apply lighting and fog.
   vec4 fragColor = vec4(0.0f, 0.0f, 0.0f, 0.0f);
   if(isParticle == 1)
   {
      vec4 texAlbedo = texture2D(tex, texCoord);

      vec4 dirLightDirect = (dirLightColor * occlusionFactor) + (dirLightAmbient * occlusionFactor) + (dirShadowColor * (1.0f - occlusionFactor));
      vec4 plt = accumulateParticlePointLights();

      vec4 lightTotal = dirLightDirect + plt;
      lightTotal.x = clamp(lightTotal.x, 0.0f, 1.2f);
      lightTotal.y = clamp(lightTotal.y, 0.0f, 1.2f);
      lightTotal.z = clamp(lightTotal.z, 0.0f, 1.2f);

      fragColor = texAlbedo * gl_Color * lightTotal;

      applyFog(fragColor);
      fragColor.a = texAlbedo.a * gl_Color.a;
   }
   else
   {
      applyLighting(fragColor, albedo, occlusionFactor);
      applyFog(fragColor);
   }

   // Uncomment to viz depth in B.
   //fragColor.z = vPos.y * 0.01f;

   gl_FragColor = fragColor;
   // gl_FragColor = vec4(occlusionFactor, occlusionFactor, occlusionFactor, 1);
}
