Shader "Custom/OceanSurface"
{
    Properties
    {
        _MainTex("Base (RGB)", 2D) = "white" {}
        _DisplacementMap ("Displacement", 2D) = "white" {}
        _NormalMap("Normal", 2D) = "white" {}
        _EdgeLength("Tessellation", Range(1,128)) = 4
        _Metal("Metallic", Range(0, 1)) = 0
        _WaterFogColor("Water Fog Color", Color) = (0, 0, 0, 0)
        _WaterFogDensity("Water Fog Density", Range(0, 2)) = 0.1
        _WaveFoamDir("Wave foam direction", Vector) = (0, 0, 0, 0)
        _FoamColor("Foam Color", Color) = (0, 0, 0, 0)
        _RefractionStrength("Refraction Strength", Range(0, 1)) = 0.5
        _SSSPower("SSS Power", Float) = 0
        _SSSColor("SSS Color", Color) = (0, 0, 0, 0)
        _WindGusts("Wind Gusts", 2D) = "white" {}
        _FoamBubbles("Foam Bubbles", 2D) = "white" {}
        _FoamEnergy("Foam Energy", 2D) = "white" {}
        _SunThreshold("Sun Threshold", Float) = 1
    }
    SubShader
    {
        ZWrite on
        Cull back
        Colormask 0
        Lighting Off

        CGPROGRAM

        #pragma surface surf Standard vertex:vert tessellate:tess nometa
        #include "UnityCG.cginc"
        #include "Tessellation.cginc"

        struct Input {
            float2 uv_MainTex;
        };


        sampler2D _DisplacementMap;

        float _Choppiness;
        float3 _ViewOrigin;
        float3 _SnappedWorldPosition;
        float3 _SnappedUVPosition;
        float _Displacement;
        float _InvDomainSize;
        float _EdgeLength;



        float computeWeight(float3 worldPos)
        {
            float d = distance(worldPos, float3(_SnappedWorldPosition.x, _ViewOrigin.y, _SnappedWorldPosition.z));
            float w = saturate(d * _InvDomainSize * 2.0f);
            return smoothstep(0.0f, 0.1f, 1.0f - w);
        }

        float4 tess(appdata_full v0, appdata_full v1, appdata_full v2)
        {
            return UnityEdgeLengthBasedTess(v0.vertex, v1.vertex, v2.vertex, _EdgeLength);
        }

        void vert(inout appdata_full v) {
            float2 uv = _SnappedUVPosition.xz + v.texcoord.xy;
            float3 displacement = tex2Dlod(_DisplacementMap, float4(uv, 0, 0)).xyz;
            float3 worldPos = mul(unity_ObjectToWorld, v.vertex);
            float w = computeWeight(worldPos);
            v.vertex.xyz += displacement * float3(_Choppiness, _Displacement * w, _Choppiness);
        }

        void surf(Input IN, inout SurfaceOutputStandard o) { }

        ENDCG


        Tags
        {
            "Queue" = "Transparent"
            "RenderType" = "Transparent"
        }
        ZWrite off
        Cull back
        Blend SrcAlpha OneMinusSrcAlpha
        Colormask RGBA
        GrabPass{ "_WaterBackground" }


        CGPROGRAM

        #pragma surface surf StandardTranslucent vertex:vert tessellate:tess nometa alpha:fade finalcolor:ResetAlpha novertexlights noforwardadd fullforwardshadows
        #include "UnityCG.cginc"
        #include "UnityPBSlighting.cginc"
        #include "Tessellation.cginc"
        #include "OceanHelper.cginc"
        #pragma target 5.0
        #pragma require tessellation tessHW

        /*struct appdata
        {
            float4 vertex   :   POSITION;
            float4 tangent  :   TANGENT;
            float3 normal   :   NORMAL;
            float2 texcoord :   TEXCOORD0;
        };*/




        struct Input
        {
            float2 uv_MainTex;
            float3 worldPos;
            float4 screenPos;
            float2 texcoord;
            float3 viewDir;
            float3 worldRefl;
            INTERNAL_DATA
        };

        sampler2D _DisplacementMap;

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
        float _Metal;
        float _Smoothness;
        float _Displacement;
        float4 _lightColor0;
        fixed4 _WaveFoamDir;
        float _RefractionStrength;
        fixed4 _SSSColor;
        half _SSSPower;
        float _SunThreshold;
        //samplerCUBE _Cube;

        float _EdgeLength;
        sampler2D _CameraDepthTexture, _WaterBackground;
        float4 _CameraDepthTexture_TexelSize;

        float3 _WaterFogColor;
        float _WaterFogDensity;

        float4 tess(appdata_full v0, appdata_full v1, appdata_full v2)
        {
            return UnityEdgeLengthBasedTess(v0.vertex, v1.vertex, v2.vertex, _EdgeLength);
        }

        float computeWeight(float3 worldPos)
        {
            float d = distance(worldPos, float3(_SnappedWorldPosition.x, _ViewOrigin.y, _SnappedWorldPosition.z));
            float w = saturate(d * _InvDomainSize * 2.0f);
            return smoothstep(0.0f, 0.1f, 1.0f - w);
        }

        void vert(inout appdata_full v)
        {
            float2 uv = _SnappedUVPosition.xz + v.texcoord.xy;
            float3 displacement = tex2Dlod(_DisplacementMap, float4(uv, 0, 0)).xyz;
            float3 worldPos = mul(unity_ObjectToWorld, v.vertex);
            float w = computeWeight(worldPos);
            v.vertex.xyz += displacement * float3(_Choppiness, _Displacement * w, _Choppiness);
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

        float3 ColorBelowWater(float4 screenPos, float3 tangentSpaceNormal) {
            float2 uvOffset = tangentSpaceNormal.xy * _RefractionStrength;
            uvOffset.y *= _CameraDepthTexture_TexelSize.z * abs(_CameraDepthTexture_TexelSize.y);
            float2 uv = AlignWithGrabTexel((screenPos.xy + uvOffset) / screenPos.w);

            float backgroundDepth =
                LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
            float surfaceDepth = UNITY_Z_0_FAR_FROM_CLIPSPACE(screenPos.z);
            float depthDifference = backgroundDepth - surfaceDepth;

            uvOffset *= saturate(depthDifference);
            uv = AlignWithGrabTexel((screenPos.xy + uvOffset) / screenPos.w);
            backgroundDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
            depthDifference = backgroundDepth - surfaceDepth;

            float3 backgroundColor = tex2D(_WaterBackground, uv).rgb;
            float fogFactor = saturate(exp2(-_WaterFogDensity * depthDifference));
            return lerp(_WaterFogColor, backgroundColor, fogFactor);
        }

        inline fixed4 LightingStandardTranslucent(SurfaceOutputStandard s, fixed3 viewDir, UnityGI gi)
        {
            // Original colour
            fixed4 pbr = LightingStandard(s, viewDir, gi);

            // Inverse Normal dot Light
            float NdotL = 1 - max(0, dot(gi.light.dir, s.Normal));

            // ViewDir dot Normal
            float VdotN = max(0, dot(viewDir, s.Normal));

            // ViewDir dot LightDir
            float VdotL = max(0, dot(normalize(-_ViewOrigin.xyz), gi.light.dir));

            float SSS = NdotL * VdotN * VdotL * _SSSPower;

            float3 L = gi.light.dir;
            float3 V = viewDir;
            float3 N = s.Normal;

            float3 H = normalize(L + N);
            float I = pow(saturate(dot(V, -H)), _SSSPower);

            // Final add
            pbr.rgb = pbr.rgb + gi.light.color * I;
            //return pbr;
            return pbr;
        }

        void LightingStandardTranslucent_GI(SurfaceOutputStandard s, UnityGIInput data, inout UnityGI gi)
        {
            LightingStandard_GI(s, data, gi);
        }

        void ResetAlpha(Input IN, SurfaceOutputStandard o, inout fixed4 color)
        {
            color.a = 1;
        }

        float ProjectedRoughness(float3 Direction, float2 Roughness)
        {
            // Simplified case, assuming the distribution of slopes is centered
            return sqrt(dot(Roughness, Direction.xy * Direction.xy));
        }

        float EffectiveFresnel(float3 V, float3 N, float2 secondOrderMomentsLowestLOD)
        {
            float r = (1.0 - 1.33) * (1.0 - 1.33) / ((1.0 + 1.33) * (1.0 + 1.33));
            float s = ProjectedRoughness(V, secondOrderMomentsLowestLOD);
            return r + (1.0 - r) * pow(1.0 - dot(N, V), 5.0 * exp(-2.69 * s)) / (1.0 + 22.7 * pow(s, 1.5));
            //return r + (1.0 - r) * pow(1.0 - dot(N, V), 5.0);
        }

        float fresnelcal(float VdotN, float eta)
        {
            float sqr_eta = eta * eta; 
            float etaCos = eta * VdotN; 
            float sqr_etaCos = etaCos * etaCos; 
            float one_minSqrEta = 1.0 - sqr_eta;
            float value = etaCos - sqrt(one_minSqrEta + sqr_etaCos);
            value *= value / one_minSqrEta; 
            return min(1.0, value * value); 
        }

        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            float2 uv = IN.uv_MainTex + _SnappedUVPosition.xz + IN.texcoord;
            //float4 d = tex2D(_DisplacementMap, uv);
            //float2 uvd = IN.worldPos.xz * _InvDomainSize + d.xz * -_Choppiness;
            float4 grad = tex2D(_NormalMap, uv);
            
            
            float foam = grad.w * grad.w;

            

            float foamDensityMapLowFrequency = tex2D(_FoamEnergy, IN.worldPos.xz * 0.24f).x - 1.0f;
            float foamDensityMapHighFrequency = tex2D(_FoamEnergy, IN.worldPos.xz * 0.35f).x - 1.0f;
            float foamDensityMapVeryHighFrequency = tex2D(_FoamEnergy, IN.worldPos.xz * 0.5f).x;
            float4 foamBubbles = tex2D(_FoamBubbles, IN.worldPos.xz * 0.45f).r;

            float foamDensity = saturate(foamDensityMapHighFrequency + min(3.5, 1.0 * foam - 0.2));
            foamDensity += (foamDensityMapLowFrequency + min(1.5, 1.0 * foam));
            foamDensity = max(0, foamDensity);
            foamDensity += max(0, foamDensityMapVeryHighFrequency * 2.0 * foam);
            foamBubbles = saturate(5.0 * (foamBubbles - 0.8));
            foamDensity = saturate(foamDensity * foamBubbles);
            
            
            float4 c = tex2D(_MainTex, uv) * lerp(_Color, _FoamColor, foamDensity);
            
            float3 n = normalize(float3(grad.xy, _NormalTexelSize));
            float3 windGusts = tex2D(_WindGusts, IN.worldPos.xz * 0.0001).x * tex2D(_WindGusts, IN.worldPos.xz * 0.00001).x;

            float3 n1 = normalize(tex2D(_WindGusts, uv * 10 * -_Time.x));// *5 * _Time.x));
            //float3 n2 = normalize(tex2D(_WindGusts, uv * 7 * _Time.x));
            float nn = float3(normalize(n1.xy + n.xy), n.z);

            float fresnel = EffectiveFresnel(IN.viewDir, n, 1.0f + 2.0f * windGusts);

            //float3 worldRefl = reflect(IN.viewDir.xzy, n.xzy);
            half4 skyData = UNITY_SAMPLE_TEXCUBE (unity_SpecCube0, IN.worldRefl);
            half3 skyColor = DecodeHDR(skyData, unity_SpecCube0_HDR);
            half reflectionFactor = dot(IN.viewDir, n);
            float fresnel2 = fresnelcal(dot(normalize(IN.viewDir), n * windGusts), 0.6);
            float3 reflcol = lerp(c.rgb, skyColor, reflectionFactor);

            float3 waterNormal = n;//lerp(n1, n, foamDensity);
            float w = computeWeight(IN.worldPos);

            //float3 foam = ((IN.worldPos.y + crestFactor) / 2)* (1 - noFoam);



            float alpha = saturate(c.a + foam);

            float4 lightColor = max(0, dot(_WorldSpaceLightPos0.xyz, reflect(-IN.viewDir.xzy, n.xzy))) * _LightColor0;
            lightColor.a = (lightColor.a > 0.98f + _SunThreshold * 0.02f);

            if (w == 0.0f)
                discard;
            //c = float4(lerp(c.rgb, ColorBelowWater(IN.screenPos), 0.5).rgb, c.a);
            o.Albedo = c.rgb;// +lightColor * lightColor.a;
            o.Normal = waterNormal;
            o.Smoothness = saturate(_Smoothness - foam);
            o.Metallic = _Metal;
            o.Alpha = c.a;
            float3 emiss = ColorBelowWater(IN.screenPos, o.Normal) * (1 - c.a);
            o.Emission = emiss * reflcol;//lerp(float3(0, 0, 1), emiss, height);
        }
        ENDCG
    }
}
