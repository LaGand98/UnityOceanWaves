// Upgrade NOTE: commented out 'float3 _WorldSpaceCameraPos', a built-in variable

Shader "Custom/UnderwaterFogShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Mask("Texture", 2D) = "white" {}
        _DepthFogDensity("Depth Fog",  Vector) = (0.9, 0.3, 0.35, 1.0)
        _WaterFogColor("Water Fog", Color) = (0, 0, 1)
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
        _NormalMap("Normal", 2D) = "white" {}
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always
        GrabPass{ "_WaterBackground" }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment sampling
            #pragma multi_compile_fog
            #define FOG_DISTANCE

            #include "UnityCG.cginc"
            #include "OceanHelper.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                uint id : SV_VertexID;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float2 uv2 : TEXCOORD3;
                float4 vertex : SV_POSITION;
                float3 viewVector : TEXCOORD1;
                #if defined(FOG_DISTANCE)
                    float3 ray : TEXCOORD2;
                #endif
            };

            float3 _FrustumCorners[4];

            float2 GetFullScreenTriangleTexCoord(uint vertexID)
            {
#if UNITY_UV_STARTS_AT_TOP
                return float2((vertexID << 1) & 2, 1.0 - (vertexID & 2));
#else
                return float2((vertexID << 1) & 2, vertexID & 2);
#endif
            }

            float4 GetFullScreenTriangleVertexPosition(uint vertexID, float z = UNITY_NEAR_CLIP_VALUE)
            {
                float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
                return float4(uv * 2.0 - 1.0, z, 1.0);
            }

            float2 TransformTriangleVertexToUV(float2 vertex)
            {
                float2 uv = (vertex + 1.0) * 0.5;
                return uv;
            }

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = GetFullScreenTriangleVertexPosition(v.id);
                o.uv = GetFullScreenTriangleTexCoord(v.id); //o.uv = TransformTriangleVertexToUV(v.vertex.xy);
                o.uv2 = v.uv;//TransformTriangleVertexToUV(v.vertex.xy);
                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv.xy * 2 - 1, 0, -1));
                o.viewVector = mul(unity_CameraToWorld, float4(viewVector, 0));
                #if defined(FOG_DISTANCE)
                o.ray = _FrustumCorners[v.uv.x + 2 * v.uv.y];
                #endif
                return o;
            }

            sampler2D _MainTex;
            sampler2D _Mask;
            sampler2D _CameraDepthTexture;
            float4 _TintShade;
            float4 _DepthFogDensity;
            float3 _WaterFogColor;

            half3 _SubSurfaceColor;
            half3 _SubSurfaceSunFallOff;
            half4 _Diffuse;
            half4 _DiffuseGrazing;
            half _SubSurfaceBase;
            half _SubSurfaceSun;
            float4x4 _InvViewProject;

            // float3 _WorldSpaceCameraPos;

            half MeniscusStrength(half2 uv, half4 mask, half offset)
            {
                half w1 = mask > 0 ? 1 : -1;
                half4 mask2 = tex2D(_Mask, half2(uv.x, uv.y + offset * w1));
                return mask2 != mask ? 1 : 1.4;
            }

            half3 ScatterColor(half3 viewDir, half3 ambientLighting)
            {
                float v = abs(viewDir.y);
                half3 col = lerp(_DiffuseGrazing, _Diffuse, v);
                col *= ambientLighting;
                half towardsSun = pow(max(0., dot(_WorldSpaceLightPos0.xyz, viewDir)), 1);
                half3 subsurface = (_SubSurfaceBase + _SubSurfaceSun * towardsSun) * _SubSurfaceColor.rgb * _LightColor0;
                subsurface *= (1.0 - v * v);
                col += subsurface;
                return col * 0.4;
            }

            fixed3 GetFogColor(half3 viewDir, fixed4 mask, half3 scene, half fogDistance)
            {
                half3 scatter = ScatterColor(viewDir, half3(1, 1, 1));
                return scatter;//lerp(scene, scatter, 1.0 - exp(-_DepthFogDensity.xyz * fogDistance));
            }

            sampler2D _CausticsTexture;
            float _CausticsDistortionStrength;
            float3 _CausticsTextureAverage;
            float3 _CausticsFocalDepth;
            float _CausticsDepthOfField;
            float _CausticsTextureScale;
            float _CausticsDistortionScale;
            sampler2D _NormalMap;
            float _CausticsStrength;
            float _OceanDepth;
            sampler2D _WaterBackground;
            sampler2D _Displacements;
            float TexelWidth;

            float2 WorldToUV(in float2 samplePos, in float2 posSnapped, in float texelWidth, in float textureRes)
            {
                return (samplePos - posSnapped) / (texelWidth * textureRes) + 0.5;
            }

            void Caustics(in const float3 i_scenePos, in const half3 i_lightDir, in const float i_sceneZ, inout half3 io_sceneColour, in half disp
            )
            {
                half waterHeight = _OceanDepth + disp;
                half sceneDepth = waterHeight - i_scenePos.y;
                float mipLod = log2(max(i_sceneZ, 1.0)) + abs(sceneDepth - _CausticsFocalDepth) / _CausticsDepthOfField;
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
                {
                    float2 surfacePosXZ = i_scenePos.xz;

                    surfacePosXZ += lightProjection;
                    half4 distortionTex = tex2D(_NormalMap, surfacePosXZ / distortionSize);
                    half2 causticN = _CausticsDistortionStrength * UnpackNormal(distortionTex).xy;
                    cuv1.xy += 1.30 * causticN;
                    cuv2.xy += 1.77 * causticN;
                }

                half causticsStrength = _CausticsStrength;
                io_sceneColour.xyz *= 1.0 + causticsStrength *
                    (
                        0.5 * tex2Dlod(_CausticsTexture, float4(cuv1.xy, 0, cuv1.z)).xyz +
                        0.5 * tex2Dlod(_CausticsTexture, float4(cuv2.xy, 0, cuv2.z)).xyz -
                        _CausticsTextureAverage
                        );
            }

            fixed4 sampling(v2f iTexCoord) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(iTexCoord);
                fixed4 sceneColor = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_MainTex, iTexCoord.uv);//tex2D(_MainTex, iTexCoord.uv);
                fixed4 maskColor = tex2D(_Mask, iTexCoord.uv);
                bool underwater = maskColor > 0;
                if (underwater)
                {
                    float rawDepth = tex2D(_CameraDepthTexture, iTexCoord.uv).r;
                    float depth = Linear01Depth(rawDepth);
                    float viewDistance = depth * _ProjectionParams.z - _ProjectionParams.y;
                    #if defined(FOG_DISTANCE)
                    viewDistance = length(iTexCoord.ray * depth);
                    #endif
                    float3 positionWS = ComputeWorldSpacePosition(iTexCoord.uv, rawDepth, _InvViewProject);
                    half3 viewDir = normalize(_WorldSpaceCameraPos - positionWS);
                    //const half3 viewDir = normalize(iTexCoord.viewVector);
                    fixed3 fogColor = GetFogColor(viewDir, maskColor, sceneColor, depth);

                    float absHeight = abs(_WorldSpaceCameraPos);
                    absHeight = absHeight < 1 ? 1 : absHeight;
                    float fogWeight = absHeight * 0.1f;

                    float fogFactor = fogWeight * viewDistance;
                    fogFactor = exp2(-fogFactor * fogFactor);

                    fogFactor = saturate(fogFactor);
                    /*if (rawDepth > 0.9999) {
                        fogFactor = 1;
                    }*/
                    float3 scenePos = _WorldSpaceCameraPos - viewDir * depth / dot(UNITY_MATRIX_I_V._13_23_33, viewDir);
                    float disp = tex2D(_Displacements, WorldToUV(scenePos, float2(0, 0), TexelWidth, 512));
                    Caustics(scenePos, _WorldSpaceLightPos0, depth, sceneColor.xyz, disp);
                    sceneColor.xyz = lerp(fogColor, sceneColor.xyz, fogFactor);
                }
                sceneColor.xyz *= MeniscusStrength(iTexCoord.uv, maskColor, 0.01);
                return sceneColor;
            }
            ENDCG
        }
    }
}
