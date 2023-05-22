#include "UnityStandardBRDF.cginc"

samplerCUBE _Cube;

float3 WaveNormal(float3 position, float amplitude, float wavelength, float speed, float2 direction, float steepness) {

	half frequency = 2 / wavelength;
	half phaseConstantSpeed = speed * 2 / wavelength;

	half2 normalizedDir = normalize(direction);
	half fi = _Time.x * phaseConstantSpeed;
	half dirDotPos = dot(normalizedDir, position.xz);

	float WA = frequency * amplitude;
	float S = sin(frequency * dirDotPos + fi);
	float C = cos(frequency * dirDotPos + fi);

	float3 normal = float3 (
		normalizedDir.x * WA * C,
		min(0.2f, steepness * WA * S),
		normalizedDir.y * WA * C
		);

	return normal;
}

float4 WavePoint(float2 position, float amplitude, float wavelength, float speed, float2 direction, float steepness, float fadeSpeed) {
	half frequency = 2 / wavelength;
	half phaseConstantSpeed = speed * 2 / wavelength;


	half2 normalizedDir = normalize(direction);
	half fi = _Time.x * phaseConstantSpeed;
	half dirDotPos = dot(normalizedDir, position);

	half fade = cos(fadeSpeed * _Time.x) / 2 + 0.5;
	amplitude *= fade;

	float waveGretsX = steepness * amplitude * normalizedDir.x * cos(frequency * dirDotPos + fi);
	float crest = sin(frequency * dirDotPos + fi);
	float waveGretsY = amplitude * crest;
	float waveGretsZ = steepness * amplitude * normalizedDir.y * cos(frequency * dirDotPos + fi);
	float crestFactor = crest * saturate(steepness) * fade;

	return float4(waveGretsX, waveGretsY, waveGretsZ, crestFactor);
}

float4 FullScreenTriangleV(uint id, float FarPlane = UNITY_NEAR_CLIP_VALUE)
{
	float2 uv = float2((id << 1) & 2, id & 2);
	return float4(uv * 2.0 - 1.0, FarPlane, 1.0);
}

float2 FullScreenTriangleUV(uint id)
{
#if UNITY_UV_STARTS_AT_TOP
	return float2((id << 1) & 2, 1.0 - (id & 2));
#else
	return float2((id << 1) & 2, id & 2);
#endif
}

// Taken and modified from:
// com.unity.render-pipelines.core@10.5.0/ShaderLibrary/Common.hlsl
float4 ComputeClipSpacePosition(float2 positionNDC, float deviceDepth)
{
	float4 positionCS = float4(positionNDC * 2.0 - 1.0, deviceDepth, 1.0);
	// positionCS.y was flipped here but that is SRP specific to solve flip baked into matrix.
	return positionCS;
}

// Taken from:
// com.unity.render-pipelines.core@10.5.0/ShaderLibrary/Common.hlsl
float3 ComputeWorldSpacePosition(float2 positionNDC, float deviceDepth, float4x4 invViewProjMatrix)
{
	float4 positionCS = ComputeClipSpacePosition(positionNDC, deviceDepth);
	float4 hpositionWS = mul(invViewProjMatrix, positionCS);
	return hpositionWS.xyz / hpositionWS.w;
}