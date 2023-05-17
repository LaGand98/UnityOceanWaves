sampler2D _MainTex;

struct Attributes
{
    uint id : SV_VertexID;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f
{
	float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    UNITY_VERTEX_OUTPUT_STEREO
};


v2f vert(Attributes i)
{
    UNITY_SETUP_INSTANCE_ID(i);
    v2f o;
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    o.positionCS = FullScreenTriangleV(i.id, _FarPlaneOffset);
    o.uv = FullScreenTriangleUV(i.id);
	return o;
}

sampler2D _CameraDepthTexture;

half4 frag(const v2f i, const bool isFrontFace : SV_IsFrontFace) : SV_TARGET
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    float3 positionWS = ComputeWorldSpacePosition(i.uv, _FarPlaneOffset, UNITY_MATRIX_I_VP);
    return (half4) positionWS.y > _OceanCenterPosWorld.y ? (half4)-1 : (half4)1;
}