namespace Ocean
{
    using System.Collections;
    using System.Collections.Generic;
    using UnityEngine;
    using System;
    using UnityEngine.Rendering;

    public class FFTScript : MonoBehaviour
    {
        enum PatchType
        {
            Interior,
            Fat,
            FatX,
            FatXSlimZ,
            FatXOuter,
            FatXZ,
            FatXZOuter,
            SlimX,
            SlimXZ,
            SlimXFatZ,
            Count,
        }

        public Material combineMaterial;
        public Material uMaterial;

        public int resolution;
        public float _loopPeriod;
        public float _windSpeed;
        public float _windTurbulence;
        public Vector2 _windDirRad;
        public float _depth;
        public float _fetch;

        int kernelSpectrum;
        int kernelSpectrumInit;
        int kernelFFTX = 0;
        int kernelFFTY = 1;
        const int firstSize = 8;

        private RenderTexture bufferSpectrumH0;
        private RenderTexture bufferSpectrumH;
        private RenderTexture bufferSpectrumDx;
        private RenderTexture bufferSpectrumDy;
        // Final
        private RenderTexture bufferHFinal;
        private RenderTexture bufferDxFinal;
        private RenderTexture bufferDyFinal;

        // FFT
        private RenderTexture bufferFFTTemp;
        private Texture2D ButterflyTex;

        private RenderTexture bufferDisplacement;
        private RenderTexture bufferGradientFold;

        private int meshSize = 128;

        private List<Vector3> extendedVertices = new List<Vector3>();
        private List<int> extendedTriangles = new List<int>();

        private Texture2D aTexture;
        private RenderTexture rTex;

        public Camera cam;

        public ComputeShader fftSpectrum;
        public ComputeShader fftCompute;

        public Mesh mesh;
        public Mesh meshExtended;
        public Material material;
        public Material materialExtended;
        public Material underWaterMask;
        public Material oceanMask;
        public Shader maskShader;

        public float domainSize = 200.0f;
        public float choppiness = 2.0f;
        public Color colorMain = Color.blue;
        public Color colorFoam = Color.white;
        public float metal = 1.0f;
        public float smoothness = 1.0f;
        public float displacement = 0.3f;
        public bool wireframe;
        public bool debug;

        public static MeshRenderer rend;


        RenderTexture CreateSpectrumUAV()
        {
            var uav = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBFloat);
            uav.enableRandomWrite = true;
            uav.Create();
            return uav;
        }

        RenderTexture CreateFinalTexture()
        {
            var texture = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.RFloat);
            texture.enableRandomWrite = true;
            texture.Create();
            return texture;
        }

        RenderTexture CreateCombinedTexture()
        {
            var texture = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBFloat);
            texture.enableRandomWrite = true;
            texture.useMipMap = true;
            texture.autoGenerateMips = true;
            texture.filterMode = FilterMode.Bilinear;
            texture.wrapMode = TextureWrapMode.Repeat;
            texture.Create();
            return texture;
        }

        void InitializeButterfly()
        {
            int log2Size = Mathf.RoundToInt(Mathf.Log(resolution, 2));

            var butterflyData = new Vector2[resolution * log2Size];

            int offset = 1;
            int numIterations = resolution >> 1;
            for (int rowIndex = 0; rowIndex < log2Size; rowIndex++)
            {
                int rowOffset = rowIndex * resolution;
                {
                    int start = 0, end = 2 * offset;
                    for (int i = 0; i < numIterations; i++)
                    {
                        float bigK = 0f;
                        for (int K = start; K < end; K += 2)
                        {
                            float phase = 2.0f * Mathf.PI * bigK * numIterations / resolution;
                            float cos = Mathf.Cos(phase);
                            float sin = Mathf.Sin(phase);
                            butterflyData[rowOffset + K / 2].x = cos;
                            butterflyData[rowOffset + K / 2].y = -sin;

                            butterflyData[rowOffset + K / 2 + offset].x = -cos;
                            butterflyData[rowOffset + K / 2 + offset].y = sin;

                            bigK += 1.0f;
                        }
                        start += 4 * offset;
                        end = start + 2 * offset;
                    }
                }
                numIterations >>= 1;
                offset <<= 1;
            }
            var butterflyBytes = new byte[butterflyData.Length * sizeof(ushort) * 2];
            for (uint i = 0; i < butterflyData.Length; i++)
            {
                uint byteOffset = i * sizeof(ushort) * 2;
                HalfHelper.SingleToHalf(butterflyData[i].x, butterflyBytes, byteOffset);
                HalfHelper.SingleToHalf(butterflyData[i].y, butterflyBytes, byteOffset + sizeof(ushort));
            }
            ButterflyTex = new Texture2D(resolution, log2Size, TextureFormat.RGHalf, false);
            ButterflyTex.LoadRawTextureData(butterflyBytes);
            ButterflyTex.Apply(false, true);
        }

        void KernelOffset()
        {
            kernelFFTX = 12; // Mathf.RoundToInt(Mathf.Log(resolution / 8, 2f));
            kernelFFTY = kernelFFTX + 1;
        }

        static Mesh BuildOceanPatch(PatchType pt, float vertDensity, out Bounds bounds)
        {
            ArrayList verts = new ArrayList();
            ArrayList indices = new ArrayList();

            // stick a bunch of verts into a 1m x 1m patch (scaling happens later)
            float dx = 1f / vertDensity;


            //////////////////////////////////////////////////////////////////////////////////
            // verts

            // see comments within PatchType for diagrams of each patch mesh

            // skirt widths on left, right, bottom and top (in order)
            float skirtXminus = 0f, skirtXplus = 0f;
            float skirtZminus = 0f, skirtZplus = 0f;
            // set the patch size
            if (pt == PatchType.Fat) { skirtXminus = skirtXplus = skirtZminus = skirtZplus = 1f; }
            else if (pt == PatchType.FatX || pt == PatchType.FatXOuter) { skirtXplus = 1f; }
            else if (pt == PatchType.FatXZ || pt == PatchType.FatXZOuter) { skirtXplus = skirtZplus = 1f; }
            else if (pt == PatchType.FatXSlimZ) { skirtXplus = 1f; skirtZplus = -1f; }
            else if (pt == PatchType.SlimX) { skirtXplus = -1f; }
            else if (pt == PatchType.SlimXZ) { skirtXplus = skirtZplus = -1f; }
            else if (pt == PatchType.SlimXFatZ) { skirtXplus = -1f; skirtZplus = 1f; }

            float sideLength_verts_x = 1f + vertDensity + skirtXminus + skirtXplus;
            float sideLength_verts_z = 1f + vertDensity + skirtZminus + skirtZplus;

            float start_x = -0.5f - skirtXminus * dx;
            float start_z = -0.5f - skirtZminus * dx;
            float end_x = 0.5f + skirtXplus * dx;
            float end_z = 0.5f + skirtZplus * dx;

            for (float j = 0; j < sideLength_verts_z; j++)
            {
                // interpolate z across patch
                float z = Mathf.Lerp(start_z, end_z, j / (sideLength_verts_z - 1f));

                // push outermost edge out to horizon
                if (pt == PatchType.FatXZOuter && j == sideLength_verts_z - 1f)
                    z *= 100f;

                for (float i = 0; i < sideLength_verts_x; i++)
                {
                    // interpolate x across patch
                    float x = Mathf.Lerp(start_x, end_x, i / (sideLength_verts_x - 1f));

                    // push outermost edge out to horizon
                    if (i == sideLength_verts_x - 1f && (pt == PatchType.FatXOuter || pt == PatchType.FatXZOuter))
                        x *= 100;

                    // could store something in y, although keep in mind this is a shared mesh that is shared across multiple lods
                    verts.Add(new Vector3(x, 0f, z));
                }
            }


            //////////////////////////////////////////////////////////////////////////////////
            // indices

            int sideLength_squares_x = (int)sideLength_verts_x - 1;
            int sideLength_squares_z = (int)sideLength_verts_z - 1;

            for (int j = 0; j < sideLength_squares_z; j++)
            {
                for (int i = 0; i < sideLength_squares_x; i++)
                {
                    bool flipEdge = false;

                    if (i % 2 == 1) flipEdge = !flipEdge;
                    if (j % 2 == 1) flipEdge = !flipEdge;

                    int i0 = i + j * (sideLength_squares_x + 1);
                    int i1 = i0 + 1;
                    int i2 = i0 + (sideLength_squares_x + 1);
                    int i3 = i2 + 1;

                    if (!flipEdge)
                    {
                        // tri 1
                        indices.Add(i3);
                        indices.Add(i1);
                        indices.Add(i0);

                        // tri 2
                        indices.Add(i0);
                        indices.Add(i2);
                        indices.Add(i3);
                    }
                    else
                    {
                        // tri 1
                        indices.Add(i3);
                        indices.Add(i1);
                        indices.Add(i2);

                        // tri 2
                        indices.Add(i0);
                        indices.Add(i2);
                        indices.Add(i1);
                    }
                }
            }


            //////////////////////////////////////////////////////////////////////////////////
            // create mesh

            Mesh mesh = new Mesh();
            if (verts != null && verts.Count > 0)
            {
                Vector3[] arrV = new Vector3[verts.Count];
                verts.CopyTo(arrV);

                int[] arrI = new int[indices.Count];
                indices.CopyTo(arrI);

                mesh.SetIndices(null, MeshTopology.Triangles, 0);
                mesh.vertices = arrV;
                mesh.normals = null;
                mesh.SetIndices(arrI, MeshTopology.Triangles, 0);

                // recalculate bounds. add a little allowance for snapping. in the chunk renderer script, the bounds will be expanded further
                // to allow for horizontal displacement
                mesh.RecalculateBounds();
                bounds = mesh.bounds;
                bounds.extents = new Vector3(bounds.extents.x + dx, bounds.extents.y, bounds.extents.z + dx);
                mesh.bounds = bounds;
                mesh.name = pt.ToString();
            }
            else
            {
                bounds = new Bounds();
            }

            return mesh;
        }

        public static float TexelWidth;

        void OnEnable()
        {
            kernelSpectrum = fftSpectrum.FindKernel("spectrumUpdate");
            kernelSpectrumInit = fftSpectrum.FindKernel("spectrumInit");

            bufferFFTTemp = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.RGFloat);
            bufferFFTTemp.enableRandomWrite = true;
            bufferFFTTemp.Create();

            bufferSpectrumH0 = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGBFloat);
            bufferSpectrumH0.enableRandomWrite = true;
            bufferSpectrumH0.Create();

            bufferSpectrumH = CreateSpectrumUAV();
            bufferSpectrumDx = CreateSpectrumUAV();
            bufferSpectrumDy = CreateSpectrumUAV();
            bufferHFinal = CreateFinalTexture();
            bufferDxFinal = CreateFinalTexture();
            bufferDyFinal = CreateFinalTexture();
            bufferDisplacement = CreateCombinedTexture();
            bufferGradientFold = CreateCombinedTexture();
            aTexture = new Texture2D(resolution, resolution);
            rTex = new RenderTexture(cam.pixelWidth, cam.pixelHeight, 0, RenderTextureFormat.ARGB32);
            InitializeButterfly();
            KernelOffset();

            Bounds meshBounds = new Bounds();
            int lodDataResolution = 384;
            int geoDownSampleFactor = 2;
            float horizScale = Mathf.Pow(2f, 8);
            float geoGridWidth =  2 * Mathf.Pow(2f, 4) / (0.25f * lodDataResolution / geoDownSampleFactor);
            var tileResolution = 2 * Mathf.Round(0.25f * lodDataResolution / geoDownSampleFactor);
            float texelWidth = geoGridWidth / geoDownSampleFactor;
            Debug.Log(texelWidth);
            mesh = BuildOceanPatch((PatchType)0, tileResolution, out meshBounds);
            this.transform.localScale = new Vector3(horizScale, 0, horizScale);
            material.SetFloat("TexelWidth", texelWidth);
            uMaterial.SetFloat("TexelWidth", texelWidth);
            TexelWidth = texelWidth;
        }

        MeshFilter meshfil;
        void Start()
        {
            rend = GetComponent<MeshRenderer>();
            meshfil = GetComponent<MeshFilter>();
            meshfil.mesh = mesh;
            rend.sortingOrder = -7;
        }

        void SpectrumInit()
        {
            fftSpectrum.SetTexture(kernelSpectrumInit, "ResultSpectrum", bufferSpectrumH0);
            fftSpectrum.SetInt("size", resolution);
            fftSpectrum.SetFloat("domainSize", domainSize);
            fftSpectrum.SetFloat("inputWindspeed", _windSpeed);
            fftSpectrum.SetFloat("inputDepth", _depth);
            fftSpectrum.SetFloat("fetch", _fetch);
            fftSpectrum.Dispatch(kernelSpectrumInit, resolution / 8, resolution / 8, 1);
        }

        void SpectrumUpdate(float time)
        {
            fftSpectrum.SetFloat("time", time);
            fftSpectrum.SetTexture(kernelSpectrum, "inputH0", bufferSpectrumH0);
            fftSpectrum.SetTexture(kernelSpectrum, "outputH", bufferSpectrumH);
            fftSpectrum.SetTexture(kernelSpectrum, "outputDx", bufferSpectrumDx);
            fftSpectrum.SetTexture(kernelSpectrum, "outputDy", bufferSpectrumDy);
            fftSpectrum.Dispatch(kernelSpectrum, resolution / 8, resolution / 8, 1);
        }

        void FFT(RenderTexture spectrum, RenderTexture output)
        {
            fftCompute.SetTexture(kernelFFTX, "input", spectrum);
            fftCompute.SetTexture(kernelFFTX, "inputButterfly", ButterflyTex);
            fftCompute.SetTexture(kernelFFTX, "output", bufferFFTTemp);
            fftCompute.Dispatch(kernelFFTX, 1, resolution, 1);

            fftCompute.SetTexture(kernelFFTY, "input", bufferFFTTemp);
            fftCompute.SetTexture(kernelFFTY, "inputButterfly", ButterflyTex);
            fftCompute.SetTexture(kernelFFTY, "output", output);
            fftCompute.Dispatch(kernelFFTY, resolution, 1, 1);
        }

        void Combine(float time)
        {
            combineMaterial.SetInt("size", resolution);
            combineMaterial.SetFloat("domainSize", domainSize);
            combineMaterial.SetFloat("invDomainSize", 1.0f / domainSize);
            combineMaterial.SetFloat("choppiness", choppiness);
            combineMaterial.SetFloat("time", time);

            combineMaterial.SetTexture("inputH", bufferHFinal);
            combineMaterial.SetTexture("inputDx", bufferDxFinal);
            combineMaterial.SetTexture("inputDy", bufferDyFinal);

            Graphics.SetRenderTarget(new RenderBuffer[] { bufferDisplacement.colorBuffer, bufferGradientFold.colorBuffer }, bufferDisplacement.depthBuffer);
            GL.PushMatrix();
            GL.LoadPixelMatrix(0, resolution, resolution, 0);
            GL.Viewport(new Rect(0, 0, resolution, resolution));
            combineMaterial.SetPass(0);
            GL.Begin(GL.QUADS);
            GL.TexCoord2(0, 0);
            GL.Vertex3(0, 0, 0);
            GL.TexCoord2(1, 0);
            GL.Vertex3(resolution, 0, 0);
            GL.TexCoord2(1, 1);
            GL.Vertex3(resolution, resolution, 0);
            GL.TexCoord2(0, 1);
            GL.Vertex3(0, resolution, 0);
            GL.End();
            GL.PopMatrix();
            Graphics.SetRenderTarget(null);
        }

        Vector3 GetPlaneBase(Vector3 n, int index)
        {
            if (index == 1)
            {
                if (n.x == 0.0f)
                {
                    return Vector3.right;
                }
                else if (n.y == 0.0f)
                {
                    return Vector3.up;
                }
                else if (n.z == 0.0f)
                {
                    return Vector3.forward;
                }
                return new Vector3(-n.y, n.x, 0.0f);
            }
            return Vector3.Cross(n, GetPlaneBase(n, 1));
        }

        Vector2 To2D(Vector3 n, Vector3 p)
        {
            var v1 = GetPlaneBase(n, 1);
            var v2 = GetPlaneBase(n, 2);
            var v3 = n;

            float denom = v2.y * v3.x * v1.z - v2.x * v3.y * v1.z + v3.z * v2.x * v1.y +
                   v2.z * v3.y * v1.x - v3.x * v2.z * v1.y - v2.y * v3.z * v1.x;
            float x = -(v2.y * v3.z * p.x - v2.y * v3.x * p.z + v3.x * v2.z * p.y +
                      v2.x * v3.y * p.z - v3.z * v2.x * p.y - v2.z * v3.y * p.x) / denom;
            float y = (v1.y * v3.z * p.x - v1.y * v3.x * p.z - v3.y * p.x * v1.z +
                    v3.y * v1.x * p.z + p.y * v3.x * v1.z - p.y * v3.z * v1.x) / denom;

            return new Vector2(x, y);
        }

        Vector3? GetIntersection(Vector3 planeOrigin, Vector3 planeNormal, Vector3 p0, Vector3 p1)
        {
            float den = Vector3.Dot(planeNormal, p1 - p0);
            if (Mathf.Abs(den) < float.Epsilon)
            {
                return null;
            }
            float u = Vector3.Dot(planeNormal, planeOrigin - p0) / den;
            if (u < 0.0f || u > 1.0f)
            {
                return null;
            }
            return p0 + u * (p1 - p0);
        }

        void AddPoint(List<Vector3> points, Vector3? point)
        {
            if (point.HasValue)
            {
                points.Add(point.Value);
            }
        }

        void DrawDebug(Vector3 point, Color color)
        {
            float size = 0.4f;
            Debug.DrawLine(point - new Vector3(size, 0.0f, 0.0f), point + new Vector3(size, 0.0f, 0.0f), color);
            Debug.DrawLine(point - new Vector3(0.0f, size, 0.0f), point + new Vector3(0.0f, size, 0.0f), color);
            Debug.DrawLine(point - new Vector3(0.0f, 0.0f, size), point + new Vector3(0.0f, 0.0f, size), color);
        }

        bool OrderedPointsCompare(Vector2 center, Vector2 a, Vector2 b)
        {
            if (a.x - center.x >= 0 && b.x - center.x < 0)
                return true;
            if (a.x - center.x < 0 && b.x - center.x >= 0)
                return false;
            if (a.x - center.x == 0 && b.x - center.x == 0)
            {
                if (a.y - center.y >= 0 || b.y - center.y >= 0)
                    return a.y > b.y;
                return b.y > a.y;
            }

            // compute the cross product of vectors (center -> a) x (center -> b)
            float det = (a.x - center.x) * (b.y - center.y) - (b.x - center.x) * (a.y - center.y);
            if (det < 0)
                return true;
            if (det > 0)
                return false;

            // points a and b are on the same line from the center
            // check which point is closer to the center
            float d1 = (a.x - center.x) * (a.x - center.x) + (a.y - center.y) * (a.y - center.y);
            float d2 = (b.x - center.x) * (b.x - center.x) + (b.y - center.y) * (b.y - center.y);
            return d1 > d2;
        }

        void ComputeExtendedPlane()
        {
            var nearTL = cam.ViewportToWorldPoint(new Vector3(1, 0, cam.nearClipPlane));
            var nearTR = cam.ViewportToWorldPoint(new Vector3(1, 1, cam.nearClipPlane));
            var nearBL = cam.ViewportToWorldPoint(new Vector3(0, 0, cam.nearClipPlane));
            var nearBR = cam.ViewportToWorldPoint(new Vector3(0, 1, cam.nearClipPlane));
            var farTL = cam.ViewportToWorldPoint(new Vector3(1, 0, cam.farClipPlane));
            var farTR = cam.ViewportToWorldPoint(new Vector3(1, 1, cam.farClipPlane));
            var farBL = cam.ViewportToWorldPoint(new Vector3(0, 0, cam.farClipPlane));
            var farBR = cam.ViewportToWorldPoint(new Vector3(0, 1, cam.farClipPlane));

            var planeOrigin = new Vector3(cam.transform.position.x, 0.0f, cam.transform.position.z);
            var planeNormal = Vector3.up;

            var points = new List<Vector3>();
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, nearTL, farTL));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, nearTR, farTR));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, nearBL, farBL));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, nearBR, farBR));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, farTL, farTR));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, farBL, farBR));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, farTL, farBL));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, farTR, farBR));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, nearTL, nearTR));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, nearBL, nearBR));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, nearTL, nearBL));
            AddPoint(points, GetIntersection(planeOrigin, planeNormal, nearTR, nearBR));
            if (points.Count == 0)
            {
                return;
            }

            var center = Vector2.zero;
            var points2D = new List<Vector2>();
            foreach (var p in points)
            {
                var p2D = To2D(planeNormal, p);
                center += p2D;
                points2D.Add(p2D);
            }
            center /= points.Count;

            var v1 = GetPlaneBase(planeNormal, 1);
            var v2 = GetPlaneBase(planeNormal, 2);

            points2D.Sort((a, b) => OrderedPointsCompare(center, a, b) ? -1 : 1);

            extendedVertices.Clear();
            extendedTriangles.Clear();

            extendedVertices.Add(v1 * center.x + v2 * center.y);
            for (int i = 0; i < points2D.Count; i++)
            {
                extendedVertices.Add(v1 * points2D[i].x + v2 * points2D[i].y);
                extendedTriangles.Add(0);
                extendedTriangles.Add(1 + (i + 1) % points2D.Count);
                extendedTriangles.Add(1 + i);
            }

            if (meshExtended == null)
            {
                meshExtended = new Mesh();
                meshExtended.name = "EncinoMeshExtended";
            }
            meshExtended.Clear();
            meshExtended.SetVertices(extendedVertices);
            meshExtended.SetTriangles(extendedTriangles, 0);
            meshExtended.RecalculateNormals();

            Graphics.DrawMesh(meshExtended, Matrix4x4.identity, materialExtended, gameObject.layer);
        }

        void OnPreRender()
        {
            GL.wireframe = wireframe;
        }

        void OnPostRender()
        {
            GL.wireframe = false;
        }

        void Update()
        {
            SpectrumInit();
            float time = Time.time;

            SpectrumUpdate(time);
            FFT(bufferSpectrumH, bufferHFinal);
            FFT(bufferSpectrumDx, bufferDxFinal);
            FFT(bufferSpectrumDy, bufferDyFinal);
            Combine(time);
        }

        void SetMaterial(Material m, Material mat, float snappedPositionX, float snappedPositionY)
        {
            var snappedUVPosition = new Vector4(snappedPositionX - domainSize * 0.5f, 0, snappedPositionY - domainSize * 0.5f, 1) / domainSize;

            m.SetTexture("_DisplacementMap", bufferDisplacement);
            m.SetTexture("_NormalMap", bufferGradientFold);
            m.SetColor("_Color", colorMain);
            m.SetColor("_FoamColor", colorFoam);
            m.SetFloat("_Choppiness", choppiness);
            m.SetFloat("_Displacement", displacement);
            m.SetVector("_ViewOrigin", transform.position);
            m.SetFloat("_DomainSize", domainSize);
            m.SetFloat("_InvDomainSize", 1.0f / domainSize);
            m.SetFloat("_NormalTexelSize", 2.0f * domainSize / resolution);
            m.SetVector("_SnappedWorldPosition", new Vector3(snappedPositionX, 0.0f, snappedPositionY));
            m.SetVector("_SnappedUVPosition", snappedUVPosition);
            m.SetFloat("_Metal", metal);
            m.SetFloat("_Smoothness", smoothness);
            m.SetFloat("_resolution", resolution);

            mat.SetTexture("_DisplacementMap", bufferDisplacement);
            mat.SetFloat("_Choppiness", choppiness);
            mat.SetFloat("_Displacement", displacement);
            mat.SetVector("_SnappedWorldPosition", new Vector3(snappedPositionX, 0.0f, snappedPositionY));
            mat.SetVector("_SnappedUVPosition", snappedUVPosition);
            mat.SetFloat("_InvDomainSize", 1.0f / domainSize);

        }


        void LateUpdate()
        {
            var worldPosition = transform.position;
            var spacing = domainSize / meshSize;
            var snappedPositionX = spacing * Mathf.FloorToInt(worldPosition.x / spacing);
            var snappedPositionY = spacing * Mathf.FloorToInt(worldPosition.z / spacing);
            var matrix = Matrix4x4.TRS(new Vector3(snappedPositionX, 0.0f, snappedPositionY), Quaternion.identity, new Vector3(domainSize, 1, domainSize));

            SetMaterial(material, oceanMask, snappedPositionX, snappedPositionY);
            uMaterial.SetTexture("_Displacements", bufferDisplacement);
            //Graphics.DrawMesh(mesh, matrix, material, gameObject.layer);
            //this.transform.localScale = new Vector3(domainSize, 1, domainSize);
            /*SetMaterial(materialExtended, snappedPositionX, snappedPositionY);
            ComputeExtendedPlane();*/
        }

        void OnGUI()
        {
            if (debug)
            {
                GUI.DrawTexture(new Rect(0, 0, resolution, resolution), bufferHFinal, ScaleMode.ScaleToFit, false);
            }
        }
    }
}