
Shader "Custom/Vegetation_URP"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _BumpMap ("Normal", 2D) = "bump" {}
        _OcclusionMap ("Occlusion", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0,1)) = 0.0
        _MetallicGlossMap ("Metallic Smoothness (R/A)", 2D) = "white" {}
        _EmissionMap ("Emissive", 2D) = "white" {}
        [HDR] _EmissiveColor ("Emissive Color", Color) = (0,0,0,0)
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        LOD 200

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM

            #pragma target 3.0
            #pragma vertex Vert
            #pragma fragment Frag

            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);

            TEXTURE2D(_OcclusionMap);
            SAMPLER(sampler_OcclusionMap);

            TEXTURE2D(_MetallicGlossMap);
            SAMPLER(sampler_MetallicGlossMap);

            TEXTURE2D(_EmissionMap);
            SAMPLER(sampler_EmissionMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float4 _MainTex_ST;
                float4 _BumpMap_ST;
                float4 _OcclusionMap_ST;
                float4 _MetallicGlossMap_ST;
                float4 _EmissionMap_ST;
                half _Glossiness;
                half _Metallic;
                half _OcclusionStrength;
                half4 _EmissiveColor;
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
                half3 vertexLighting : TEXCOORD4;
                half fogFactor : TEXCOORD5;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                VertexPositionInputs posInputs =
                    GetVertexPositionInputs(IN.positionOS.xyz);

                VertexNormalInputs normalInputs =
                    GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionCS = posInputs.positionCS;
                OUT.positionWS = posInputs.positionWS;
                OUT.normalWS = normalInputs.normalWS;

                OUT.tangentWS = half4(
                    normalInputs.tangentWS,
                    IN.tangentOS.w * GetOddNegativeScale()
                );

                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.vertexLighting = VertexLighting(
                    posInputs.positionWS,
                    normalInputs.normalWS
                );
                OUT.fogFactor = ComputeFogFactor(posInputs.positionCS.z);

                return OUT;
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                #ifdef LOD_FADE_CROSSFADE
                    LODFadeCrossFade(IN.positionCS);
                #endif

                float2 uv = IN.uv;

                half4 albedoSample =
                    SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv) * _Color;

                half4 metallicSample =
                    SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, uv);

                half occlusionSample =
                    SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g;

                half3 normalTS = UnpackNormal(
                    SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv)
                );

                half3 bitangentWS =
                    IN.tangentWS.w * cross(IN.normalWS, IN.tangentWS.xyz);

                half3x3 tangentToWorld = half3x3(
                    IN.tangentWS.xyz,
                    bitangentWS,
                    IN.normalWS
                );

                half3 normalWS = NormalizeNormalPerPixel(
                    TransformTangentToWorld(normalTS, tangentToWorld)
                );

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedoSample.rgb;
                surfaceData.metallic = metallicSample.r * _Metallic;
                surfaceData.specular = half3(0, 0, 0);
                surfaceData.smoothness = metallicSample.a * _Glossiness;
                surfaceData.normalTS = normalTS;
                surfaceData.emission =
                    SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb
                    * _EmissiveColor.rgb;
                surfaceData.occlusion = lerp(1.0h, occlusionSample, _OcclusionStrength);
                surfaceData.alpha = albedoSample.a;

                InputData inputData = (InputData)0;
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS =
                    GetWorldSpaceNormalizeViewDir(IN.positionWS);
                inputData.shadowCoord =
                    TransformWorldToShadowCoord(IN.positionWS);
                inputData.fogCoord = IN.fogFactor;
                inputData.vertexLighting = IN.vertexLighting;
                inputData.bakedGI = SampleSH(normalWS);
                inputData.normalizedScreenSpaceUV =
                    GetNormalizedScreenSpaceUV(IN.positionCS);
                inputData.shadowMask = half4(1, 1, 1, 1);

                half4 color = UniversalFragmentPBR(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, IN.fogFactor);

                return color;
            }

            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
