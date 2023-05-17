Shader "Unlit/OceanShader"
{
    Properties
    {
        _TessellationEdgeLength ("Tessellation Edge Length", Range(0.1, 1)) = 0.5
        _MainTex("Base (RGB)", 2D) = "white" {}
        _DisplacementMap("Displacement", 2D) = "white" {}
        _NormalMap("Normal", 2D) = "white" {}
        _EdgeLength("Tessellation", Range(1,128)) = 4
        _WaterFogColor("Water Fog Color", Color) = (0, 0, 0, 0)
        _WaterFogDensity("Water Fog Density", Vector) = (0.9, 0.3, 0.35, 1.0)
        _WaveFoamDir("Wave foam direction", Vector) = (0, 0, 0, 0)
        _FoamColor("Foam Color", Color) = (0, 0, 0, 0)
        _RefractionStrength("Refraction Strength", Range(0, 1)) = 0.5
        _WindGusts("Wind Gusts", 2D) = "white" {}
        _FoamBubbles("Foam Bubbles", 2D) = "white" {}
        _FoamEnergy("Foam Energy", 2D) = "white" {}
        _Roughness("Roughness", Range(0.0, 1.0)) = 0.0
        _Specular("Specular", Range(0.0, 1.0)) = 0.7
        _FresnelPower("FresnelPower", Range(1.0, 20.0)) = 5.0
        _DirectionalLightBoost("DirectionalLightBoost", Range(1.0, 100.0)) = 10.0
        _Diffuse("Scatter Colour Base", Color) = (0.0, 0.0026954073, 0.16981131, 1.0)
        _DiffuseGrazing("Scatter Colour Grazing", Color) = (0.0, 0.003921569, 0.1686274, 1.0)
        _SubSurfaceBase("SSS Intensity Base", Range(0.0, 4.0)) = 0.0
        _SubSurfaceSunFallOff("SSS Sun Falloff", Range(1.0, 16.0)) = 5.0
        _SubSurfaceSun("SSS Intensity Sun", Range(0.0, 10.0)) = 1.7
        _SubSurfaceColor("SSS Tint", Color) = (0.08850684, 0.497, 0.45615074, 1.0)
        _OceanDepth("Ocean Depth", Float) = 100
        _CausticsFocalDepth("Caustics Focal Depth", Range(0.0, 250.0)) = 2.0
        _CausticsDepthOfField("Caustics Depth of Field", Range(0.01, 1000.0)) = 0.33
        _CausticsDistortionStrength("Caustics Distortion Strength", Range(0.0, 0.25)) = 0.16
        _CausticsStrength("Caustics Strength", Range(0.0, 10.0)) = 3.2
        _CausticsTextureAverage("Caustics Texture Grey Point", Range(0.0, 1.0)) = 0.07
        _CausticsTexture("Caustics", 2D) = "black" {}
        _CausticsTextureScale("Caustics Scale", Range(0.0, 25.0)) = 5.0
        _CausticsDistortionScale("Caustics Distortion Scale", Range(0.01, 50.0)) = 25.0
        _TexelWidth("Texel Width", Float) = 1
    }
        SubShader
        {
            Tags 
            {
                "Queue" = "Geometry+510"
                "IgnoreProjector" = "True"
                "RenderType" = "Opaque"
                "DisableBatching" = "True" 
            }
            GrabPass{ "_WaterBackground" }

            Pass
            {
                Cull Off
                Tags
                {
                    "LightMode" = "ForwardBase"
                }
                CGPROGRAM

                #pragma target 3.0
                #pragma vertex vert
                #pragma fragment frag
                #include "UnityCG.cginc"
                #include "Lighting.cginc"
                #include "UnityPBSlighting.cginc"
                #include "OceanHelper.cginc"

                Texture2D _DisplacementMap;

                sampler2D _MainTex;
                sampler2D _NormalMap;
                sampler2D _WindGusts;
                sampler2D _FoamBubbles;
                sampler2D _FoamEnergy;

                float4 _Color;
                float4 _FoamColor;
                float _Choppiness;
                float3 _ViewOrigin;
                float _DomainSize;
                float _InvDomainSize;
                float _NormalTexelSize;
                float3 _SnappedWorldPosition;
                float3 _SnappedUVPosition;
                float _Displacement;
                float4 _lightColor0;
                fixed4 _WaveFoamDir;
                half _RefractionStrength;
                half _SunThreshold;
                half _Roughness;
                half _Specular;
                half _FresnelPower;
                half _DirectionalLightBoost;
                half3 _Diffuse;
                half3 _DiffuseGrazing;
                half _SubSurfaceBase;
                half _SubSurfaceSunFallOff;
                half _SubSurfaceSun;
                half3 _SubSurfaceColor;
                half _OceanDepth;
                half _CausticsFocalDepth;
                half _CausticsDepthOfField;
                half _CausticsDistortionStrength;
                half _CausticsStrength;
                half _CausticsTextureAverage;
                half _CausticsTextureScale;
                half _CausticsDistortionScale;

                //samplerCUBE _Cube;

                float _EdgeLength;
                sampler2D _CameraDepthTexture, _WaterBackground;
                float4 _CameraDepthTexture_TexelSize;

                float3 _WaterFogColor;
                float3 _WaterFogDensity;

                float TexelWidth;
                SamplerState LODDATA_linear_clamp_sampler;

                struct Attributes
                {
                    float4 vertex : POSITION;
                    float2 uv : TEXCOORD0;
                };

                struct v2f
                {
                    float4 clipSpacePosition    : SV_Position;
                    float3 worldSpacePosition   : TEXCOORD0;
                    float4 screenPos            : TEXCOORD3;
                    float3 viewDir              : TEXCOORD4;
                    half3 normal : TEXCOORD6;
                    float disp : TEXCOORD7;
                    float2 uv : TEXCOORD2;
                };

                float computeWeight(float3 worldPos)
                {
                    float d = distance(worldPos, float3(_SnappedWorldPosition.x, _ViewOrigin.y, _SnappedWorldPosition.z));
                    float w = saturate(d * _InvDomainSize * 2.0f);
                    return smoothstep(0.0f, 0.1f, 1.0f - w);
                }

                void SampleDisplacementsNormals(in Texture2D dispSampler, in float2 uv_slice, in float invRes, in float texelSize, in float weight, inout float2 normal)
                {
                    const half4 data = dispSampler.SampleLevel(LODDATA_linear_clamp_sampler, float3(uv_slice, 0), 0);
                    const half3 disp = data.xyz;
                    float3 dd = float3(invRes, 0.0f, texelSize);
                    float3 disp_x = dd.zyy + dispSampler.SampleLevel(LODDATA_linear_clamp_sampler, float3(uv_slice + dd.yx, 0), 0).xyz;
                    float3 disp_z = dd.yyz + dispSampler.SampleLevel(LODDATA_linear_clamp_sampler, float3(uv_slice + dd.yx, 0), 0).xyz;

                    float3 crossProd = cross(disp_z - disp, disp_x - disp);
                    float3 n = normalize(crossProd);
                    normal += weight * n.xz;
                }

                float2 WorldToUV(in float2 samplePos, in float2 posSnapped, in float texelWidth, in float textureRes)
                {
                    return (samplePos - posSnapped) / (texelWidth * textureRes) + 0.5;
                }

                float4 _DisplacementMap_TexelSize;

                v2f vert(Attributes v)
                {
                    v2f Output;
                    UNITY_INITIALIZE_OUTPUT(v2f, Output);

                    float textureRes = 512;
                    float texelWidth = TexelWidth;
                    //texelWidth = _DisplacementMap_TexelSize.x;
                    float2 posSnapped = float2(0, 0);

                    float3 worldSpacePosition = mul(UNITY_MATRIX_M, float4(v.vertex.xyz, 1.0));

                    const float2 tileCenterXZ = UNITY_MATRIX_M._m03_m23;
                    const float2 cameraPositionXZ = abs(_WorldSpaceCameraPos.xz);
                    worldSpacePosition.xz = lerp(tileCenterXZ, worldSpacePosition.xz, lerp(1.0, 1.01, max(cameraPositionXZ.x, cameraPositionXZ.y) * 0.00001));

                    float w = computeWeight(worldSpacePosition);
                    float2 UV = WorldToUV(worldSpacePosition.xz, posSnapped, texelWidth, textureRes);
                    float3 displacement = _DisplacementMap.SampleLevel(LODDATA_linear_clamp_sampler, float3(UV, 0), 0).xyz;

                    worldSpacePosition += displacement* w* _Displacement;

                    Output.clipSpacePosition = mul(UNITY_MATRIX_VP, float4(worldSpacePosition, 1.0));
                    Output.worldSpacePosition = worldSpacePosition;

                    Output.uv = UV;
                    Output.screenPos = ComputeGrabScreenPos(Output.clipSpacePosition);
                    Output.viewDir = normalize(UnityWorldSpaceViewDir(Output.worldSpacePosition));
                    float3 normal = float3(0, 1, 0);
                    SampleDisplacementsNormals(_DisplacementMap, UV, _InvDomainSize, _NormalTexelSize, w, normal.xz);
                    Output.normal = normal;
                    Output.disp = displacement.y * _Displacement * w;
                    return Output;
                }

                float CalculateFresnelReflectionCoefficient(float cosTheta)
                {
                    float R_0 = (1.0f - 1.33f) / (1.0f + 1.33f);
                    R_0 *= R_0;
                    const float R_theta = R_0 + (1.0 - R_0) * pow(max(0, 1.0 - cosTheta), _FresnelPower);
                    return R_theta;
                }

                float2 AlignWithGrabTexel(float2 uv)
                {
                    #if UNITY_UV_STARTS_AT_TOP
                    if (_CameraDepthTexture_TexelSize.y < 0) {
                        uv.y = 1 - uv.y;
                    }
                    #endif
                    return (floor(uv * _CameraDepthTexture_TexelSize.zw) + 0.5f) * abs(_CameraDepthTexture_TexelSize.xy);
                }

                half3 ScatterColor(half3 viewDir, half3 ambientLighting, bool underwater)
                {
                    float v = abs(viewDir.y);
                    half3 col = lerp(_DiffuseGrazing, _Diffuse, v);
                    col *= ambientLighting;
                    half towardsSun = pow(max(0., dot(_WorldSpaceLightPos0.xyz, -viewDir)), 1);
                    half3 subsurface = (_SubSurfaceBase + _SubSurfaceSun * towardsSun) * _SubSurfaceColor.rgb * _LightColor0;
                    if (underwater)
                        subsurface *= (1.0 - v * v);
                    return col += subsurface;
                }

                sampler2D _CausticsTexture;

                void Caustics(in const float3 i_scenePos, in const half3 i_lightDir, in const float i_sceneZ, inout half3 io_sceneColour, in half disp
                )
                {
                    // this gives height at displaced position, not exactly at query position.. but it helps. i cant pass this from vert shader
                    // because i dont know it at scene pos.
                    half waterHeight = _OceanDepth + disp;
                    half sceneDepth = waterHeight - i_scenePos.y;
                    // Compute mip index manually, with bias based on sea floor depth. We compute it manually because if it is computed automatically it produces ugly patches
                    // where samples are stretched/dilated. The bias is to give a focusing effect to caustics - they are sharpest at a particular depth. This doesn't work amazingly
                    // well and could be replaced.
                    float mipLod = log2(max(i_sceneZ, 1.0)) + abs(sceneDepth - _CausticsFocalDepth) / _CausticsDepthOfField;
                    // project along light dir, but multiply by a fudge factor reduce the angle bit - compensates for fact that in real life
                    // caustics come from many directions and don't exhibit such a strong directonality
                    // Removing the fudge factor (4.0) will cause the caustics to move around more with the waves. But this will also
                    // result in stretched/dilated caustics in certain areas. This is especially noticeable on angled surfaces.
                    float2 lightProjection = i_lightDir.xz * sceneDepth / (4.0 * i_lightDir.y);

                    float2 causticSize = _CausticsTextureScale;
                    float2 distortionSize = _CausticsDistortionScale;

                    float3 cuv1 = 0.0; float3 cuv2 = 0.0;
                    {
                        float2 surfacePosXZ = i_scenePos.xz;
                        float surfacePosScale = 1.37;
                        surfacePosXZ += lightProjection;

                        cuv1 = float3
                            (
                                surfacePosXZ / causticSize + float2(0.044 * _Time.y + 17.16, -0.169 * _Time.y),
                                mipLod
                                );
                        cuv2 = float3
                            (
                                surfacePosScale * surfacePosXZ / causticSize + float2(0.248 * -_Time.y, 0.117 * -_Time.y),
                                mipLod
                                );
                    }
                    // Apply distortion.
                    {
                        float2 surfacePosXZ = i_scenePos.xz;

                        surfacePosXZ += lightProjection;
                        half4 distortionTex = tex2D(_NormalMap, surfacePosXZ / distortionSize);
                        half2 causticN = _CausticsDistortionStrength * UnpackNormal(distortionTex).xy;
                        cuv1.xy += 1.30 * causticN;
                        cuv2.xy += 1.77 * causticN;
                    }
                    //io_sceneColour = 0.5 * tex2Dlod(_CausticsTexture, float4(cuv2.xy, 0, cuv2.z)).xyz + 0.5 * tex2Dlod(_CausticsTexture, float4(cuv1.xy, 0, cuv2.z)).xyz;

                    half causticsStrength = _CausticsStrength;
                    io_sceneColour.xyz *= 1.0 + causticsStrength *
                        (
                            0.5 * tex2Dlod(_CausticsTexture, float4(cuv1.xy, 0, cuv1.z)).xyz +
                            0.5 * tex2Dlod(_CausticsTexture, float4(cuv2.xy, 0, cuv2.z)).xyz -
                            _CausticsTextureAverage
                            );
                }

                float3 ColorBelowWater(float4 screenPos, float3 waterNormal, half3 scatterColor, bool underwater, float3 viewDir, float sceneZ, half disp, float pixelZ) {
                    half3 waterColor = scatterColor;
                    half3 alpha = 0.;
                    half3 sceneColor;
                    const half2 uvBackground = screenPos.xy / screenPos.w;
                    if (!underwater)
                    {
                        float2 uvOffset = _RefractionStrength * waterNormal.xz * min(1.0, 0.5 * (sceneZ - pixelZ)) / sceneZ;
                        //uvOffset.y *= _CameraDepthTexture_TexelSize.z * abs(_CameraDepthTexture_TexelSize.y);
                        //float depthFogDistance = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(uvBackground + uvOffset, rawDepth)

                        float surfaceDepth = UNITY_Z_0_FAR_FROM_CLIPSPACE(screenPos.z);

                        float backgroundDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uvBackground + uvOffset));
                        float depthDifference = backgroundDepth - surfaceDepth;
                        uvOffset *= saturate(depthDifference);


                        sceneColor = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_WaterBackground, uvBackground + uvOffset).rgb;

                        //sceneColor = lerp(_WaterFogColor, backgroundColor, fogFactor);
                        alpha = 1.0 - exp(-_WaterFogDensity.xyz*depthDifference);
                        float3 scenePos = _WorldSpaceCameraPos - viewDir * sceneZ / dot(unity_CameraToWorld._m02_m12_m22, -viewDir);
                        Caustics(scenePos, _WorldSpaceLightPos0.xyz, sceneZ, sceneColor, half(disp));
                    }
                    else
                    {
                        const half2 uvBackground = screenPos.xy / screenPos.w;
                        half2 uvBackgroundRefractSky = uvBackground + _RefractionStrength * waterNormal.xz * 0.2;
                        sceneColor = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_WaterBackground, uvBackgroundRefractSky).rgb;
                    }
                    return lerp(sceneColor, waterColor, alpha);
                }

                void ApplyReflectionSky(const in half3 refl, const in half3 waterNormal, const in half3 viewDir, inout half3 waterColor)
                {
                    Unity_GlossyEnvironmentData envData;
                    envData.roughness = _Roughness;
                    envData.reflUVW = refl;
                    float3 probe0 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData);

                    half3 skyColor = probe0;
                    half fallOff = 257;
                    skyColor += pow(max(0., dot(refl, _WorldSpaceLightPos0.xyz)), fallOff) * _LightColor0 * _DirectionalLightBoost;
                    float R_theta = CalculateFresnelReflectionCoefficient(max(dot(waterNormal, viewDir), 0.0));
                    waterColor = lerp(waterColor, skyColor, R_theta * _Specular);
                }

                void ApplyReflectionUnderwater(in const half3 view, in const half3 waterNormal, in const float4 screenPos, half3 scatterCol, in float weight, inout half3 waterColor)
                {
                    const half3 underwaterColor = scatterCol;
                    const float cosOutgoingAngle = max(dot(waterNormal, view), 0.);
                    {
                        const float cosIngoingAngle = cos(asin(clamp((1.33f * sin(acos(cosOutgoingAngle))) / 1.0f, -1.0, 1.0)));
                        const float reflection = CalculateFresnelReflectionCoefficient(cosIngoingAngle) * weight;
                        waterColor *= (1.0 - reflection);
                        waterColor = max(waterColor, 0.0);
                    }

                    {
                        const float cosIngoingAngle = cosOutgoingAngle;
                        const float reflection = CalculateFresnelReflectionCoefficient(cosIngoingAngle) * weight;
                        waterColor += (underwaterColor * reflection);
                    }
                }

                float4 frag(v2f v, const bool isFrontFace : SV_IsFrontFace) : SV_Target
                {
                    float2 uv = v.uv;
                    float4 grad = tex2D(_NormalMap, uv);
                    float speedMul = 1;
                    const float2 v0 = float2(0.94, 0.34), v1 = float2(-0.85, -0.53);
                    float2 windGusts = UnpackNormal(tex2D(_WindGusts, (v0 * _Time.y * speedMul + v.worldSpacePosition.xz) / 5)).xy +
                        UnpackNormal(tex2D(_WindGusts, (v1 * _Time.y * speedMul + v.worldSpacePosition.xz) / 5)).xy;
                    float3 waterNormal = v.normal;
                    waterNormal.xz += windGusts * 0.7;

                    bool underwater = !isFrontFace;

                    if (underwater) waterNormal = -waterNormal;

                    float foam = grad.w;

                    foam = clamp(foam, 0, foam);

                    float foamDensityMapLowFrequency = tex2D(_FoamEnergy, v.worldSpacePosition.xz * 0.24f).x - 1.0f;
                    float foamDensityMapHighFrequency = tex2D(_FoamEnergy, v.worldSpacePosition.xz * 0.35f).x - 1.0f;
                    float foamDensityMapVeryHighFrequency = tex2D(_FoamEnergy, v.worldSpacePosition.xz * 0.5f).x;
                    float4 foamBubbles = tex2D(_FoamBubbles, v.worldSpacePosition.xz * 0.45f).r;

                    float foamDensity = saturate(foamDensityMapHighFrequency + min(3.5, 1.0 * foam - 0.2));
                    foamDensity += (foamDensityMapLowFrequency + min(1.5, 1.0 * foam));
                    foamDensity = max(0, foamDensity);
                    foamDensity += max(0, foamDensityMapVeryHighFrequency * 2.0 * foam);
                    foamBubbles = saturate(5.0 * (foamBubbles - 0.8));
                    foamDensity = saturate(foamDensity * foamBubbles) * 1.3;

                    half3 viewDir = normalize(_WorldSpaceCameraPos - v.worldSpacePosition);
                    half3 refl = reflect(-viewDir, waterNormal);
                    refl.y = max(refl.y, 0.0);
                    half3 foamColor = _FoamColor *max(0, 0.3 + max(0, 0.7 * dot(_WorldSpaceLightPos0, waterNormal)));

                    float4 c = tex2D(_MainTex, uv);

                    float3 n = grad.xyz;

                    half reflectionFactor = dot(v.viewDir, waterNormal * 0.3);

                    float w = computeWeight(v.worldSpacePosition);

                    float alpha = saturate(c.a + foam);

                    half3 scatterCol = ScatterColor(viewDir, half3(1, 1, 1), underwater);


                    float2 uvDepth = AlignWithGrabTexel(v.screenPos.xy / v.screenPos.w);;
                    float sceneZ = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uvDepth));
                    float pixelZ = LinearEyeDepth(v.worldSpacePosition.z);

                    if (w == 0.0f)
                        discard;
                    float Alpha = c.a;
                    float3 waterColor = ColorBelowWater(v.screenPos, waterNormal, scatterCol, underwater, viewDir, sceneZ, v.disp, pixelZ);

                    //Caustics(scenePos, _WorldSpaceLightPos0.xyz, sceneZ, waterColor, half(v.disp));
                    //float pixelZ = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, v.worldSpacePosition.z));
                    
                    waterColor = lerp(waterColor, foamColor * _LightColor0 * 4, foamDensity);

                    if (underwater)
                    {
                        float weight = 0.5;//saturate((sceneZ - pixelZ) / 6);
                        ApplyReflectionUnderwater(viewDir, waterNormal, v.screenPos, scatterCol, weight, waterColor);
                    }
                    else
                    {
                        ApplyReflectionSky(refl, waterNormal, viewDir, waterColor);
                    }

                    float3 tempWaterColor = waterColor;
                    waterColor = lerp(waterColor, foamColor * _LightColor0 * 4, foamDensity);
                    waterColor = clamp(waterColor, tempWaterColor, waterColor);
                    return float4(waterColor, 1);
                }
                    
                ENDCG
            }
            /*Pass
            {
                Name "SceneSelectionPass"
                Tags { "LightMode" = "MotionVectors" }
                CGPROGRAM
                #pragma vertex vert
                #pragma fragment frag
                #pragma hull hullS
                #pragma domain domainS
                #pragma require tessellation tessHW
                #pragma target 3.0
                #include "UnityCG.cginc"
                float3 _SnappedUVPosition;
                float3 _SnappedWorldPosition;
                float3 _ViewOrigin;
                float _InvDomainSize;
                sampler2D _DisplacementMap;
                float _Choppiness;
                float _Displacement;

                #include "UnderWaterMask.hlsl"

                ENDCG
            }*/
        }

}
