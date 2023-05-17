Shader "Unlit/OceanMaskShader"
{
    Properties
    {
        _DisplacementMap("Displacement", 2D) = "white" {}
    }
    SubShader
    {
        Pass
        {
            Cull Off
            ZTest Always
            ZWrite Off
            Stencil
            {
                Ref 5
                Comp Equal
            }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            float3 _SnappedUVPosition;
            float3 _SnappedWorldPosition;
            float3 _ViewOrigin;
            float _InvDomainSize;
            Texture2D _DisplacementMap;
            float _Choppiness;
            float _Displacement;
            #include "UnityCG.cginc"
            #include "UnderWaterMask.hlsl"
            ENDCG
        }

        Pass
        {
            Cull Off
            ZWrite Off
            ZTest Always

            Stencil
            {
                Ref 5
                Comp Equal
            }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "OceanHelper.cginc"
            float4x4 _InvViewProjection;
            float _FarPlaneOffset;
            float3 _OceanCenterPosWorld;
            #define UNITY_MATRIX_I_VP _InvViewProjection
            #include "UnderWaterHorizonMask.hlsl"
            ENDCG
        }

    }
}
