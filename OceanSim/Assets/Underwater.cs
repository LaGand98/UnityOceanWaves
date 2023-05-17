namespace Ocean
{
    using System.Collections;
    using System.Collections.Generic;
    using UnityEditor;
    using UnityEngine;
    using System;
    using UnityEngine.Rendering;

    public class Underwater : MonoBehaviour
    {
        RenderTexture rTex;
        public Material underWaterMask;
        public Material underWaterEffect;
        Mesh mesh;

        [NonSerialized]
        Camera _camera;

        [NonSerialized]
        Vector3[] frustumCorners;

        [NonSerialized]
        Vector4[] vectorArray;

        private Dictionary<Camera, CommandBuffer> Cameras = new Dictionary<Camera, CommandBuffer>();

        void OnEnable()
        {
            _camera = GetComponent<Camera>();
            _camera.depthTextureMode = _camera.depthTextureMode | DepthTextureMode.Depth;
            rTex = new RenderTexture(_camera.pixelWidth, _camera.pixelHeight, 0, RenderTextureFormat.ARGB32);
            frustumCorners = new Vector3[4];
            vectorArray = new Vector4[4];
        }

        void OceanMask(Camera cam, Material mat, Material mat2, Matrix4x4 matrix, Renderer renderer)
        {
            if (Cameras.ContainsKey(cam))
                return;

            CommandBuffer cmd = new CommandBuffer();
            Cameras[cam] = cmd;

            RenderTargetIdentifier maskTarget = new RenderTargetIdentifier(rTex, 0, CubemapFace.Unknown, depthSlice: -1);
            cmd.SetRenderTarget(rTex);
            mat.SetVector("_OceanCenterPosWorld", new Vector3(0, 0, 0)); // Get Real Coordinates -> easy
            float zBufferParamsX; float zBufferParamsY;
            if (SystemInfo.usesReversedZBuffer)
            {
                zBufferParamsY = 1f;
                zBufferParamsX = _camera.farClipPlane / _camera.nearClipPlane - 1f;
            }
            else
            {
                zBufferParamsY = _camera.farClipPlane / _camera.nearClipPlane;
                zBufferParamsX = 1f - zBufferParamsY;
            }
            float farPlaneMultiplier = 0.68f;
            var farPlaneLerp = (1f - zBufferParamsY * farPlaneMultiplier) / (zBufferParamsX * farPlaneMultiplier);
            underWaterMask.SetFloat("_FarPlaneOffset", farPlaneLerp);
            cmd.DrawProcedural(Matrix4x4.identity, mat, 1, MeshTopology.Triangles, 3, 1);

            cmd.DrawRenderer(renderer, mat, 0, 0);
            cam.AddCommandBuffer(CameraEvent.AfterSkybox, cmd);
        }

        Matrix4x4 _gpuInverseViewProjectionMatrix;

        void OnPreRender()
        {
            _gpuInverseViewProjectionMatrix = (GL.GetGPUProjectionMatrix(_camera.projectionMatrix, false) * _camera.worldToCameraMatrix).inverse;
            underWaterMask.SetMatrix("_InvViewProject", _gpuInverseViewProjectionMatrix);
            Renderer renderer = FFTScript.rend;
            OceanMask(_camera, underWaterMask, underWaterEffect, Matrix4x4.identity, renderer);
        }

        // Start is called before the first frame update
        void Start()
        {
            underWaterMask.SetFloat("TexelWidth", FFTScript.TexelWidth);
        }

        // Update is called once per frame
        void Update()
        {
            underWaterEffect.SetTexture("_Mask", rTex);
        }

        

        [ImageEffectOpaque]
        void OnRenderImage(RenderTexture source, RenderTexture destination)
        {
            _camera.CalculateFrustumCorners(
                new Rect(0f, 0f, 1f, 1f),
                _camera.farClipPlane,
                _camera.stereoActiveEye,
                frustumCorners);


            vectorArray[0] = frustumCorners[0];
            vectorArray[1] = frustumCorners[3];
            vectorArray[2] = frustumCorners[1];
            vectorArray[3] = frustumCorners[2];
            underWaterEffect.SetVectorArray("_FrustumCorners", vectorArray);

            Graphics.Blit(source, destination, underWaterEffect);
        }
    }
}
