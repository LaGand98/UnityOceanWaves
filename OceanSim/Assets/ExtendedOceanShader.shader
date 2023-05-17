Shader "Custom/ExtendedOceanShader"
{
	Properties
	{
		_MainTex("Base (RGB)", 2D) = "white" {}
		_Cube("Reflection Cubemap", Cube) = "_Skybox" {}
		_WaterFogColor("Water Fog Color", Color) = (0, 0, 0, 0)
		_WaterFogDensity("Water Fog Density", Range(0, 2)) = 0.1
		_WaveFoamDir("Wave foam direction", Vector) = (0, 0, 0, 0)
		_FoamColor("Foam Color", Color) = (0, 0, 0, 0)
	}
		SubShader
	{
		Tags { "RenderType" = "Opaque" }
		LOD 300
		Cull Off

		CGPROGRAM
		#pragma surface surf Standard nolightmap vertex:vert
		#pragma target 5.0
		#pragma enable_d3d11_debug_symbols
		#include "OceanHelper.cginc"

		struct Input
		{
			float2 uv_MainTex;
			float3 worldPos;
			float3 worldRefl;
			float4 screenPos;
			INTERNAL_DATA
		};

		sampler2D _MainTex;
		sampler2D _DispTex;
		sampler2D _NormalMap;
		float3 _SnappedWorldPosition;
		float3 _ViewOrigin;
		float _Choppiness;
		float _DomainSize;
		float _InvDomainSize;
		float _NormalTexelSize;
		float4 _Color;
		float4 _ColorFoam;
		float _Metal;
		float _Smoothness;

		float3 _WaterFogColor;
		float _WaterFogDensity;

		sampler2D _CameraDepthTexture, _WaterBackground;


		void vert(inout appdata_full v)
		{
			float2 uv = 1 + 2;
			float3 displacement = float3(0, 0, 0);//tex2Dlod(_DisplacementMap, float4(uv, 0, 0)).xyz;
			float3 worldPos = mul(unity_ObjectToWorld, v.vertex);
			float w = 1;
			v.vertex.xyz += displacement * float3(1, 1 * w, 1);
			/*o.worldRefl = float3(1, 1, 1);
			o.worldPos = float3(1, 1, 1);
			o.uv_MainTex = float2(1, 1);*/
		}

		float computeWeight(float3 worldPos)
		{
			float d = distance(worldPos, float3(_SnappedWorldPosition.x, _ViewOrigin.y, _SnappedWorldPosition.z)) - _DomainSize * 0.5f;
			float w = saturate(d * _InvDomainSize * 1.0f);
			return smoothstep(0.0f, 0.1f, w);
		}

		float3 ColorBelowWater(float4 screenPos) {
			float2 uv = screenPos.xy / screenPos.w;
			float backgroundDepth =
				LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
			float surfaceDepth = UNITY_Z_0_FAR_FROM_CLIPSPACE(screenPos.z);
			float depthDifference = backgroundDepth - surfaceDepth;
			float3 backgroundColor = tex2D(_WaterBackground, uv).rgb;
			float fogFactor = exp2(-_WaterFogDensity * depthDifference);
			return lerp(_WaterFogColor, backgroundColor, fogFactor);
		}

		void surf(Input v, inout SurfaceOutputStandard o)
		{
			float2 uv = v.worldPos.xz * _InvDomainSize;
			float4 d = tex2D(_DispTex, uv);
			float2 uvd = v.worldPos.xz * _InvDomainSize + d.xz * -_Choppiness;
			float4 grad = tex2D(_NormalMap, uvd);
			float foam = grad.w * grad.w;
			float4 c = tex2D(_MainTex, uvd) * lerp(_Color, _ColorFoam, foam);
			float3 n = normalize(float3(grad.xy, _NormalTexelSize));
			float w = computeWeight(v.worldPos);
			if (w == 0.0f)
			{
				discard;
			}

			float alpha = 0.1;

			o.Albedo = c;
			o.Normal = n;
			o.Smoothness = lerp(_Smoothness, 0, foam);
			o.Emission = ColorBelowWater(v.screenPos) * (1 - alpha);
		}
		ENDCG
	}
	FallBack Off
}
