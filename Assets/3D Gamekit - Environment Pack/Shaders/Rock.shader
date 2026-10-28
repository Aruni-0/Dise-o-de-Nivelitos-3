
Shader "Custom/Rock_URP"
{
    Properties
    {
        _MainTex ("Albedo", 2D) = "white" {}
        [NoScaleOffset] _BumpMap ("Normal", 2D) = "bump" {}
        [NoScaleOffset] _DetailBump ("Detail Normal", 2D) = "bump" {}
        _DetailScale ("Detail Scale", Float) = 1.0

        [NoScaleOffset] _OcclusionMap ("Occlusion", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0,1)) = 1.0

        [NoScaleOffset] _MetallicRough ("Metallic/Roughness (RGBA)", 2D) = "white" {}
        [Gamma] _Metallic ("Metallic", Range(0,1)) = 0
        _Glossiness ("Smoothness", Range(0,1)) = 0.5

        [NoScaleOffset] _TopAlbedo ("Top Albedo", 2D) = "white" {}
        [NoScaleOffset] _TopNormal ("Top Normal", 2D) = "bump" {}
        [NoScaleOffset] _TopMetallicRough ("Top Metallic/Roughness (RGBA)", 2D) = "white" {}
        [Gamma] _TopMetallic ("Top Metallic", Range(0,1)) = 0
        _TopGlossiness ("Top Smoothness", Range(0,1)) = 0.5

        [NoScaleOffset] _Noise ("Noise", 2D) = "white" {}
        _TopScale ("Top Texture Scale", Float) = 1.0
        _NoiseScale ("Noise Texture Scale", Float) = 1.0
        _NoiseAmount ("Noise Amount", Range(0,1)) = 1.0
        _NoiseFallOff ("Noise Falloff", Range(0.01,1)) = 0.2
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        LOD 300
        Cull Back

        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_BumpMap);
        SAMPLER(sampler_BumpMap);
        TEXTURE2D(_DetailBump);
        SAMPLER(sampler_DetailBump);
        TEXTURE2D(_OcclusionMap);
        SAMPLER(sampler_OcclusionMap);
        TEXTURE2D(_MetallicRough);
        SAMPLER(sampler_MetallicRough);
        TEXTURE2D(_TopAlbedo);
        SAMPLER(sampler_TopAlbedo);
        TEXTURE2D(_TopNormal);
        SAMPLER(sampler_TopNormal);
        TEXTURE2D(_TopMetallicRough);
        SAMPLER(sampler_TopMetallicRough);
        TEXTURE2D(_Noise);
        SAMPLER(sampler_Noise);

        CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            half _DetailScale;
            half _OcclusionStrength;
            half _Metallic;
            half _Glossiness;
            half _TopMetallic;
            half _TopGlossiness;
            half _TopScale;
            half _NoiseScale;
            half _NoiseAmount;
            half _NoiseFallOff;
        CBUFFER_END

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
            float4 tangentOS : TANGENT;
            float2 uv : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float3 positionWS : TEXCOORD0;
            half3 normalWS : TEXCOORD1;
            half4 tangentWS : TEXCOORD2;
            float2 uv : TEXCOORD3;
            half fogFactor : TEXCOORD4;
            UNITY_VERTEX_INPUT_INSTANCE_ID
            UNITY_VERTEX_OUTPUT_STEREO
        };

        half3 BlendRNM(half3 n1, half3 n2)
        {
            n1.z += 1.0h;
            n2.xy = -n2.xy;
            return n1 * dot(n1, n2) / max(n1.z, 0.0001h) - n2;
        }

        Varyings Vert(Attributes IN)
        {
            Varyings OUT = (Varyings)0;

            UNITY_SETUP_INSTANCE_ID(IN);
            UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

            VertexPositionInputs pos =
                GetVertexPositionInputs(IN.positionOS.xyz);

            VertexNormalInputs norm =
                GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

            OUT.positionCS = pos.positionCS;
            OUT.positionWS = pos.positionWS;
            OUT.normalWS = norm.normalWS;
            OUT.tangentWS = half4(
                norm.tangentWS,
                IN.tangentOS.w * GetOddNegativeScale()
            );
            OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
            OUT.fogFactor = ComputeFogFactor(pos.positionCS.z);

            return OUT;
        }

        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag

            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            half4 Frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                #if defined(LOD_FADE_CROSSFADE)
                    LODFadeCrossFade(IN.positionCS);
                #endif

                // Geometric world normal and triplanar top projection
                half3 geomNormal = normalize(IN.normalWS);
                float2 uvTop = IN.positionWS.xz * _TopScale;

                half4 noiseTex = SAMPLE_TEXTURE2D(
                    _Noise, sampler_Noise, uvTop * _NoiseScale
                );

                half topFacing = saturate(geomNormal.y);
                half blend = smoothstep(
                    noiseTex.r,
                    1.0h,
                    topFacing
                );

                half noiseBlend = smoothstep(
                    0.1h,
                    max(0.101h, 0.1h + _NoiseFallOff),
                    blend
                );

                noiseBlend = saturate(noiseBlend * _NoiseAmount);

                // Base material normals in tangent space
                half3 baseNormal = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _BumpMap, sampler_BumpMap, IN.uv
                    )
                );

                half3 detailNormal = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _DetailBump, sampler_DetailBump,
                        IN.uv * _DetailScale
                    )
                );

                baseNormal = normalize(BlendRNM(baseNormal, detailNormal));

                half3 tangentWS = normalize(IN.tangentWS.xyz);
                half3 bitangentWS = normalize(
                    cross(geomNormal, tangentWS) * IN.tangentWS.w
                );

                half3x3 tangentToWorld = half3x3(
                    tangentWS, bitangentWS, geomNormal
                );

                half3 baseNormalWS = normalize(
                    TransformTangentToWorld(baseNormal, tangentToWorld)
                );

                // Top-projected normal: texture X/Y map to world X/Z.
                half3 topNormalTS = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _TopNormal, sampler_TopNormal, uvTop
                    )
                );

                half3 topNormalWS = normalize(
                    half3(topNormalTS.x, topNormalTS.z, topNormalTS.y)
                );

                // Reorient the top normal against the geometric normal.
                half3 topBase = normalize(
                    half3(geomNormal.x, geomNormal.z, abs(geomNormal.y))
                );

                topNormalWS = normalize(
                    BlendRNM(topBase, topNormalTS)
                );

                topNormalWS = normalize(
                    half3(topNormalWS.x, topNormalWS.z, topNormalWS.y)
                );

                half3 finalNormalWS = normalize(
                    lerp(baseNormalWS, topNormalWS, noiseBlend)
                );

                // Albedo
                half3 baseAlbedo = SAMPLE_TEXTURE2D(
                    _MainTex, sampler_MainTex, IN.uv
                ).rgb;

                half3 topAlbedo = SAMPLE_TEXTURE2D(
                    _TopAlbedo, sampler_TopAlbedo, uvTop
                ).rgb;

                half3 albedo = lerp(
                    baseAlbedo, topAlbedo, noiseBlend
                );

                // Occlusion
                half occSample = SAMPLE_TEXTURE2D(
                    _OcclusionMap, sampler_OcclusionMap, IN.uv
                ).g;

                half occlusion = lerp(
                    1.0h, occSample, _OcclusionStrength
                );

                // Metallic and smoothness
                half4 baseMR = SAMPLE_TEXTURE2D(
                    _MetallicRough, sampler_MetallicRough, IN.uv
                );

                half4 topMR = SAMPLE_TEXTURE2D(
                    _TopMetallicRough, sampler_TopMetallicRough, uvTop
                );

                half metallic = lerp(
                    baseMR.r * _Metallic,
                    noiseTex.r * _TopMetallic,
                    noiseBlend
                );

                half smoothness = lerp(
                    baseMR.a * _Glossiness,
                    topMR.a * _TopGlossiness,
                    noiseBlend
                );

                // URP physically based lighting
                InputData inputData = (InputData)0;
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = finalNormalWS;
                inputData.viewDirectionWS =
                    GetWorldSpaceNormalizeViewDir(IN.positionWS);
                inputData.shadowCoord =
                    TransformWorldToShadowCoord(IN.positionWS);
                inputData.fogCoord = IN.fogFactor;
                inputData.vertexLighting = half3(0,0,0);
                inputData.bakedGI = SampleSH(finalNormalWS);
                inputData.normalizedScreenSpaceUV =
                    GetNormalizedScreenSpaceUV(IN.positionCS);
                inputData.shadowMask = half4(1,1,1,1);

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedo;
                surfaceData.metallic = metallic;
                surfaceData.specular = half3(0,0,0);
                surfaceData.smoothness = smoothness;
                surfaceData.normalTS = baseNormal;
                surfaceData.emission = half3(0,0,0);
                surfaceData.occlusion = occlusion;
                surfaceData.alpha = 1;
                surfaceData.clearCoatMask = 0;
                surfaceData.clearCoatSmoothness = 0;

                half4 color = UniversalFragmentPBR(
                    inputData, surfaceData
                );

                color.rgb = MixFog(color.rgb, IN.fogFactor);

                return color;
            }

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            ShadowVaryings ShadowVert(Attributes IN)
            {
                ShadowVaryings OUT = (ShadowVaryings)0;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                VertexPositionInputs pos =
                    GetVertexPositionInputs(IN.positionOS.xyz);

                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);

                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                    float3 lightDir = normalize(_LightPosition - pos.positionWS);
                #else
                    float3 lightDir = _LightDirection;
                #endif

                float3 biasedPosition = ApplyShadowBias(
                    pos.positionWS, normalWS, lightDir
                );

                OUT.positionCS = TransformWorldToHClip(biasedPosition);

                #if UNITY_REVERSED_Z
                    OUT.positionCS.z = min(
                        OUT.positionCS.z,
                        OUT.positionCS.w * UNITY_NEAR_CLIP_VALUE
                    );
                #else
                    OUT.positionCS.z = max(
                        OUT.positionCS.z,
                        OUT.positionCS.w * UNITY_NEAR_CLIP_VALUE
                    );
                #endif

                return OUT;
            }

            half4 ShadowFrag(ShadowVaryings IN) : SV_Target
            {
                return 0;
            }

            ENDHLSL
        }
    }

    FallBack Off
}
