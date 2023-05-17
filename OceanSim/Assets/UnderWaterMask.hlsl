sampler2D _MainTex;

struct Attributes
{
	float4 vertex : POSITION;
    //UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f
{
	float4 clipSpacePosition : SV_POSITION;
    //UNITY_VERTEX_OUTPUT_STEREO
};

float computeWeight(float3 worldPos)
{
    float d = distance(worldPos, float3(_SnappedWorldPosition.x, _ViewOrigin.y, _SnappedWorldPosition.z));
    float w = saturate(d * _InvDomainSize * 2.0f);
    return smoothstep(0.0f, 0.1f, 1.0f - w);
}

float2 WorldToUV(in float2 samplePos, in float2 posSnapped, in float texelWidth, in float textureRes)
{
    return (samplePos - posSnapped) / (texelWidth * textureRes) + 0.5;
}

float4 _DisplacementMap_TexelSize;
float TexelWidth;

SamplerState LODDATA_linear_clamp_sampler;

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

    worldSpacePosition += displacement * w * _Displacement;

    Output.clipSpacePosition = mul(UNITY_MATRIX_VP, float4(worldSpacePosition, 1.0));
    return Output;
}

half4 frag(const v2f i, const bool isFrontFace : SV_IsFrontFace) : SV_TARGET
{
	if (isFrontFace)
		return (half4)-1;
    else
		return (half4)1;
}