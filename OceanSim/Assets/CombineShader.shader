Shader "Custom/CombineShader"
{
    Properties
    {
        inputH("H", 2D) = "white" {}
        inputDx("Dx", 2D) = "white" {}
        inputDy("Dy", 2D) = "white" {}
        //_textureDynamicSkyDome("Dynamic Sky Dome", 2D) = "white" {}
    }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag
            #include "UnityCG.cginc"

            int size;
            float domainSize;
            float invDomainSize;
            float choppiness;
            float deltaTime;

            Texture2D<float> inputH;
            Texture2D<float> inputDx;
            Texture2D<float> inputDy;


            float3 SampleDisplacement(int2 coord)
            {
                coord.x += coord.x < 0 ? size : (coord.x >= size ? -size : 0);
                coord.y += coord.y < 0 ? size : (coord.y >= size ? -size : 0);
                return float3(inputDx[coord], inputH[coord], inputDy[coord]) *float3(1, 1.0f, 1);
            }

            void frag(v2f_img i, out float4 outDisplacement : SV_Target0, out float4 outGradientFold : SV_Target1)
            {
                int2 coord = floor(i.pos.xy);
                {
                    outDisplacement = float4(SampleDisplacement(coord), 1);
                }

                {
                    float3 dispL = SampleDisplacement(coord + int2(-1, 0));
                    float3 dispR = SampleDisplacement(coord + int2(+1, 0));
                    float3 dispT = SampleDisplacement(coord + int2(0, -1));
                    float3 dispB = SampleDisplacement(coord + int2(0, +1));

                    float3 diffH = dispR - dispL;
                    float3 diffV = dispB - dispT;

                    float2 Dx = diffH.xz * choppiness * size * invDomainSize;
                    float2 Dy = diffV.xz * choppiness * size * invDomainSize;

                    float J = (1.0f + Dx.x) * (1.0f + Dy.y) - (Dx.y * Dy.x);
                    float fold = max(1.0f - saturate(J), 0);

                    outGradientFold = float4(-diffH.y, -diffV.y, 0, fold);//SampleEigen(coord));
                }
            }
            ENDCG
        }
    }
}
