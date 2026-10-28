
Shader "Custom/Dissolve_URP"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        [HDR] _Emission ("Emission", Color) = (0,0,0,0)
        _MainTex ("Albedo", 2D) = "white" {}
        _Normal ("Normal", 2D) = "bump" {}
        _MetallicSmooth ("Metallic (RGB) Smooth (A)", 2D) = "white" {}
        _AO ("AO", 2D) = "white" {}
        [HDR] _EdgeColor1 ("Edge Color", Color) = (1,1,1,1)
        _Noise ("Noise", 2D) = "white" {}
        [Toggle(_USE_GRADIENT_ON)] _Use_Gradient ("Use Gradient?", Float) = 1
        _Gradient ("Gradient", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
        _Cutoff ("Cutoff", Range(0,1)) = 0.0
        _EdgeSize ("EdgeSize", Range(0,1)) = 0.2
        _NoiseStrength ("Noise Strength", Range(0,1)) = 0.4
        _DisplaceAmount ("Displace Amount", Range(0,1)) = 0.4
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "AlphaTest"
            "RenderType" = "TransparentCutout"
            "IgnoreProjector" = "True"
        }

        Cull Off
        LOD 200

        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_Normal);
        SAMPLER(sampler_Normal);
        TEXTURE2D(_MetallicSmooth);
        SAMPLER(sampler_MetallicSmooth);
        TEXTURE2D(_AO);
        SAMPLER(sampler_AO);
        TEXTURE2D(_Noise);
        SAMPLER(sampler_Noise);
        TEXTURE2D(_Gradient);
        SAMPLER(sampler_Gradient);

        CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            float4 _Emission;
            float4 _EdgeColor1;
            float4 _MainTex_ST;
            float4 _Normal_ST;
            float4 _MetallicSmooth_ST;
            float4 _AO_ST;
            float4 _Noise_ST;
            float4 _Gradient_ST;
            half _Glossiness;
            half _Metallic;
            half _Cutoff;
            half _EdgeSize;
            half _NoiseStrength;
            half _DisplaceAmount;
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
            float2 uvMain : TEXCOORD3;
            float2 uvNoise : TEXCOORD4;
            float2 uvGradient : TEXCOORD5;
            half fogFactor : TEXCOORD6;
            UNITY_VERTEX_INPUT_INSTANCE_ID
            UNITY_VERTEX_OUTPUT_STEREO
        };

        float3 DisplaceVertex(float3 positionOS, float3 normalOS, float2 uv)
        {
            float3 positionWS = TransformObjectToWorld(positionOS);

            // Animated noise sampled in world XZ.
            float2 noiseUV = positionWS.xz * 0.5;
            noiseUV.x += _Time.y * 15.0;

            half noiseValue = SAMPLE_TEXTURE2D_LOD(
                _Noise, sampler_Noise, noiseUV, 0
            ).r;

            half gradientValue = SAMPLE_TEXTURE2D_LOD(
                _Gradient, sampler_Gradient,
                TRANSFORM_TEX(uv, _Gradient), 0
            ).r;

            // Preserve the original displacement mask behavior.
            half mask = 1.0h - smoothstep(
                _Cutoff - 0.3h,
                _Cutoff,
                1.0h - gradientValue
            );

            positionOS += normalOS * noiseValue * mask
                        * _Cutoff * _DisplaceAmount;

            return positionOS;
        }

        half CalculateEdge(float2 uvMain, float2 uvNoise)
        {
            half noiseValue = SAMPLE_TEXTURE2D(
                _Noise, sampler_Noise, uvNoise
            ).r;

            #if defined(_USE_GRADIENT_ON)
                half gradientValue = SAMPLE_TEXTURE2D(
                    _Gradient, sampler_Gradient,
                    TRANSFORM_TEX(uvMain, _Gradient)
                ).r;

                half value = 1.0h -
                    (gradientValue + noiseValue *
                    (1.0h - gradientValue) * _NoiseStrength);
            #else
                half value = 1.0h - noiseValue;
            #endif

            // Reversed smoothstep equivalent to the original shader.
            return 1.0h - smoothstep(
                _Cutoff - _EdgeSize,
                _Cutoff,
                value
            );
        }

        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM

            #pragma target 4.0
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma shader_feature_local_fragment _USE_GRADIENT_ON
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            Varyings Vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                IN.positionOS.xyz = DisplaceVertex(
                    IN.positionOS.xyz, IN.normalOS, IN.uv
                );

                VertexPositionInputs pos =
                    GetVertexPositionInputs(IN.positionOS.xyz);

                VertexNormalInputs nrm =
                    GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionCS = pos.positionCS;
                OUT.positionWS = pos.positionWS;
                OUT.normalWS = nrm.normalWS;
                OUT.tangentWS = half4(
                    nrm.tangentWS,
                    IN.tangentOS.w * GetOddNegativeScale()
                );

                OUT.uvMain = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.uvNoise = TRANSFORM_TEX(IN.uv, _Noise);
                OUT.uvGradient = TRANSFORM_TEX(IN.uv, _Gradient);
                OUT.fogFactor = ComputeFogFactor(pos.positionCS.z);

                return OUT;
            }

            half4 Frag(Varyings IN, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                half edge = CalculateEdge(IN.uvMain, IN.uvNoise);
                clip(1.0h - edge - _Cutoff);

                half4 albedoSample = SAMPLE_TEXTURE2D(
                    _MainTex, sampler_MainTex, IN.uvMain
                );

                half4 metallicSmooth = SAMPLE_TEXTURE2D(
                    _MetallicSmooth, sampler_MetallicSmooth,
                    TRANSFORM_TEX(IN.uvMain, _MetallicSmooth)
                );

                half ao = SAMPLE_TEXTURE2D(
                    _AO, sampler_AO, TRANSFORM_TEX(IN.uvMain, _AO)
                ).g;

                half3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(
                    _Normal, sampler_Normal, TRANSFORM_TEX(IN.uvMain, _Normal)
                ));

                half3 bitangentWS =
                    IN.tangentWS.w * cross(IN.normalWS, IN.tangentWS.xyz);

                half3x3 tangentToWorld = half3x3(
                    IN.tangentWS.xyz, bitangentWS, IN.normalWS
                );

                half3 normalWS = NormalizeNormalPerPixel(
                    TransformTangentToWorld(normalTS, tangentToWorld)
                );

                // Support both sides of the mesh.
                if (!IS_FRONT_VFACE(face, true, false))
                    normalWS = -normalWS;

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedoSample.rgb * _Color.rgb;
                surfaceData.metallic = metallicSmooth.r * _Metallic;
                surfaceData.smoothness = metallicSmooth.a * _Glossiness;
                surfaceData.normalTS = normalTS;
                surfaceData.occlusion = ao;
                surfaceData.emission =
                    albedoSample.a * _Emission.rgb +
                    _EdgeColor1.rgb * edge;
                surfaceData.alpha = 1.0h;

                InputData inputData = (InputData)0;
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS =
                    GetWorldSpaceNormalizeViewDir(IN.positionWS);
                inputData.shadowCoord =
                    TransformWorldToShadowCoord(IN.positionWS);
                inputData.fogCoord = IN.fogFactor;
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

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM

            #pragma target 4.0
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma shader_feature_local_fragment _USE_GRADIENT_ON
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uvMain : TEXCOORD0;
                float2 uvNoise : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            ShadowVaryings ShadowVert(Attributes IN)
            {
                ShadowVaryings OUT = (ShadowVaryings)0;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                IN.positionOS.xyz = DisplaceVertex(
                    IN.positionOS.xyz, IN.normalOS, IN.uv
                );

                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);

                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                    float3 lightDirectionWS =
                        normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                OUT.positionCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, normalWS, lightDirectionWS)
                );

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

                OUT.uvMain = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.uvNoise = TRANSFORM_TEX(IN.uv, _Noise);

                return OUT;
            }

            half4 ShadowFrag(ShadowVaryings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half edge = CalculateEdge(IN.uvMain, IN.uvNoise);
                clip(1.0h - edge - _Cutoff);

                return 0;
            }

            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
