
Shader "Custom/MossMask_URP"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        [Toggle(_USE_MASK_ON)] _Use_Mask ("Use mask?", Float) = 0

        _MainTex ("Albedo", 2D) = "white" {}
        [NoScaleOffset] _BumpMap ("Normal", 2D) = "bump" {}
        [NoScaleOffset] _DetailBump ("Detail Normal", 2D) = "bump" {}
        _DetailScale ("Detail Scale", Float) = 1.0

        [NoScaleOffset] _OcclusionMap ("Occlusion", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0,1)) = 1.0

        [NoScaleOffset] _MetallicRough ("Metallic/Roughness (RGBA)", 2D) = "white" {}
        [Gamma] _Metallic ("Metallic", Range(0,1)) = 0
        _Glossiness ("Smoothness", Range(0,1)) = 0.5

        _TopAlbedo ("Top Albedo", 2D) = "white" {}
        [NoScaleOffset] _TopNormal ("Top Normal", 2D) = "bump" {}
        _TopNormal2 ("Top Normal Detail", 2D) = "bump" {}

        [NoScaleOffset] _TopMetallicRough ("Top Metallic/Roughness (RGBA)", 2D) = "white" {}
        [Gamma] _TopMetallic ("Top Metallic", Range(0,1)) = 0
        _TopGlossiness ("Top Smoothness", Range(0,1)) = 0.5

        _FresnelAmount ("Fresnel Amount", Float) = 0
        _FresnelPower ("Fresnel Power", Float) = 1

        _Emission ("Emission", 2D) = "black" {}
        [HDR] _EmissiveColor ("Emissive Color", Color) = (1,1,1,1)
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

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma shader_feature_local _USE_MASK_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);

            TEXTURE2D(_DetailBump);
            SAMPLER(sampler_DetailBump);

            TEXTURE2D(_TopAlbedo);
            SAMPLER(sampler_TopAlbedo);

            TEXTURE2D(_TopNormal);
            SAMPLER(sampler_TopNormal);

            TEXTURE2D(_TopNormal2);
            SAMPLER(sampler_TopNormal2);

            TEXTURE2D(_OcclusionMap);
            SAMPLER(sampler_OcclusionMap);

            TEXTURE2D(_MetallicRough);
            SAMPLER(sampler_MetallicRough);

            TEXTURE2D(_TopMetallicRough);
            SAMPLER(sampler_TopMetallicRough);

            TEXTURE2D(_Emission);
            SAMPLER(sampler_Emission);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float4 _MainTex_ST;
                float4 _TopAlbedo_ST;
                float4 _TopNormal2_ST;

                half _DetailScale;
                half _OcclusionStrength;
                half _Metallic;
                half _Glossiness;
                half _TopMetallic;
                half _TopGlossiness;
                half _FresnelAmount;
                half _FresnelPower;
                half4 _EmissiveColor;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3 normalWS : TEXCOORD1;
                half4 tangentWS : TEXCOORD2;
                float2 uvMain : TEXCOORD3;
                float2 uvTop : TEXCOORD4;
                float2 uvTopNormal2 : TEXCOORD5;
                half fogFactor : TEXCOORD6;
            };

            half3 BlendRNM(half3 n1, half3 n2)
            {
                n1.z += 1.0h;
                n2.xy = -n2.xy;

                return n1 * dot(n1, n2) / max(n1.z, 0.0001h) - n2;
            }

            half3 SafeNormal(half3 n)
            {
                return normalize(n);
            }

            Varyings Vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;

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

                OUT.uvMain = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.uvTop = TRANSFORM_TEX(IN.uv, _TopAlbedo);
                OUT.uvTopNormal2 = TRANSFORM_TEX(IN.uv, _TopNormal2);

                OUT.fogFactor = ComputeFogFactor(pos.positionCS.z);

                return OUT;
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                #if defined(LOD_FADE_CROSSFADE)
                    LODFadeCrossFade(IN.positionCS);
                #endif

                half mask = 0.0h;

                #if defined(_USE_MASK_ON)
                    mask = SAMPLE_TEXTURE2D(
                        _MainTex, sampler_MainTex, IN.uvMain
                    ).a;
                #endif

                mask = saturate(mask);

                // Tangent-space normal maps
                half3 normalMain = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _BumpMap, sampler_BumpMap, IN.uvMain
                    )
                );

                half3 detailNormal = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _DetailBump, sampler_DetailBump,
                        IN.uvMain * _DetailScale
                    )
                );

                normalMain = SafeNormal(
                    BlendRNM(normalMain, detailNormal)
                );

                half3 topNormal = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _TopNormal, sampler_TopNormal, IN.uvTop
                    )
                );

                half3 topNormalDetail = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _TopNormal2, sampler_TopNormal2,
                        IN.uvTopNormal2
                    )
                );

                topNormal = SafeNormal(
                    BlendRNM(topNormal, normalMain)
                );

                topNormal = SafeNormal(
                    BlendRNM(topNormal, topNormalDetail)
                );

                // World-space basis
                half3 normalWS = normalize(IN.normalWS);
                half3 tangentWS = normalize(IN.tangentWS.xyz);
                half3 bitangentWS = normalize(
                    cross(normalWS, tangentWS) * IN.tangentWS.w
                );

                half3x3 tangentToWorld = half3x3(
                    tangentWS, bitangentWS, normalWS
                );

                // Fresnel on the top material
                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(
                    IN.positionWS
                );

                half3 viewDirTS = normalize(
                    TransformWorldToTangent(viewDirWS, tangentToWorld)
                );

                half fresnel = saturate(
                    1.0h - dot(SafeNormal(topNormal), viewDirTS)
                );

                fresnel = clamp(
                    pow(fresnel, max(_FresnelPower, 0.001h)),
                    0.0h, 6.0h
                );

                // Albedo
                half4 baseColor = SAMPLE_TEXTURE2D(
                    _MainTex, sampler_MainTex, IN.uvMain
                ) * _Color;

                half4 topColor = SAMPLE_TEXTURE2D(
                    _TopAlbedo, sampler_TopAlbedo, IN.uvTop
                );

                topColor.rgb += topColor.rgb *
                    (fresnel * 2.0h - 1.0h) *
                    _FresnelAmount * 0.5h;

                // Occlusion
                half occlusionSample = SAMPLE_TEXTURE2D(
                    _OcclusionMap, sampler_OcclusionMap, IN.uvMain
                ).g;

                half occlusion = lerp(
                    1.0h, occlusionSample, _OcclusionStrength
                );

                half3 albedo = lerp(
                    baseColor.rgb,
                    topColor.rgb * occlusion,
                    mask
                );

                // Metallic and smoothness: R = metallic, A = smoothness
                half4 baseMR = SAMPLE_TEXTURE2D(
                    _MetallicRough, sampler_MetallicRough, IN.uvMain
                );

                half4 topMR = SAMPLE_TEXTURE2D(
                    _TopMetallicRough,
                    sampler_TopMetallicRough, IN.uvMain
                );

                half metallic = lerp(
                    baseMR.r * _Metallic,
                    topMR.r * _TopMetallic,
                    mask
                );

                half smoothness = lerp(
                    baseMR.a * _Glossiness,
                    topMR.a * _TopGlossiness,
                    mask
                );

                // Blend tangent-space normals, then convert to world space
                half3 normalTS = SafeNormal(
                    lerp(normalMain, topNormal, mask)
                );

                half3 finalNormalWS = normalize(
                    TransformTangentToWorld(normalTS, tangentToWorld)
                );

                // Emission
                half3 emission = SAMPLE_TEXTURE2D(
                    _Emission, sampler_Emission, IN.uvMain
                ).rgb * _EmissiveColor.rgb;

                #if defined(_USE_MASK_ON)
                    emission *= (1.0h - mask * 0.99h);
                #endif

                // URP PBR input
                InputData inputData = (InputData)0;

                inputData.positionWS = IN.positionWS;
                inputData.normalWS = finalNormalWS;
                inputData.viewDirectionWS = viewDirWS;
                inputData.shadowCoord = TransformWorldToShadowCoord(
                    IN.positionWS
                );
                inputData.fogCoord = IN.fogFactor;
                inputData.vertexLighting = half3(0, 0, 0);
                inputData.bakedGI = SampleSH(finalNormalWS);
                inputData.normalizedScreenSpaceUV =
                    GetNormalizedScreenSpaceUV(IN.positionCS);
                inputData.shadowMask = half4(1, 1, 1, 1);

                SurfaceData surfaceData = (SurfaceData)0;

                surfaceData.albedo = albedo;
                surfaceData.metallic = metallic;
                surfaceData.specular = half3(0.0h, 0.0h, 0.0h);
                surfaceData.smoothness = smoothness;
                surfaceData.normalTS = normalTS;
                surfaceData.emission = emission;
                surfaceData.occlusion = occlusion;
                surfaceData.alpha = baseColor.a;
                surfaceData.clearCoatMask = 0.0h;
                surfaceData.clearCoatSmoothness = 1.0h;

                half4 color = UniversalFragmentPBR(
                    inputData, surfaceData
                );

                color.rgb = MixFog(color.rgb, IN.fogFactor);

                return color;
            }

            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }

    FallBack Off
}
