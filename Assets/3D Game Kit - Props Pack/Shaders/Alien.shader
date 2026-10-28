
Shader "Custom/Alien_URP"
{
    Properties
    {
        _MainTex ("Albedo(RGB) Emissive(A)", 2D) = "white" {}
        _NormalMap ("Normal", 2D) = "bump" {}
        _MetallicSmooth ("Metallic(RGB) Smooth(A)", 2D) = "white" {}
        _PackedMap ("_PackedMap", 2D) = "white" {}
        [HDR] _EmissiveColor ("Emissive Color", Color) = (1,1,1,1)
        [HDR] _Color ("Inner Tint", Color) = (1,1,1,1)
        _Ramp ("Edge Highlight Ramp", 2D) = "white" {}
        _Ramp2 ("Inner Structure Ramp", 2D) = "white" {}
        _marchDistance ("Inner Offset", Float) = 0.5
        _numSteps ("Inner Samples", Float) = 4
        _glowMin ("Glow Min", Float) = 0
        _glowMax ("Glow Max", Float) = 1
        _glowFrequency ("Glow Frequency", Float) = 1
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

            #pragma target 4.0
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            TEXTURE2D(_MetallicSmooth);
            SAMPLER(sampler_MetallicSmooth);

            TEXTURE2D(_PackedMap);
            SAMPLER(sampler_PackedMap);

            TEXTURE2D(_Ramp);
            SAMPLER(sampler_Ramp);

            TEXTURE2D(_Ramp2);
            SAMPLER(sampler_Ramp2);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _NormalMap_ST;
                float4 _MetallicSmooth_ST;
                float4 _PackedMap_ST;
                float4 _Ramp_ST;
                float4 _Ramp2_ST;
                half4 _Color;
                half4 _EmissiveColor;
                float _numSteps;
                float _marchDistance;
                float _glowMin;
                float _glowMax;
                float _glowFrequency;
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
                float2 uvPacked : TEXCOORD4;
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
                OUT.uvPacked = TRANSFORM_TEX(IN.uv, _PackedMap);
                OUT.fogFactor = ComputeFogFactor(pos.positionCS.z);

                return OUT;
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                half4 albedoSample =
                    SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uvMain);

                half4 metallicSmooth =
                    SAMPLE_TEXTURE2D(_MetallicSmooth, sampler_MetallicSmooth, IN.uvMain);

                half4 packed =
                    SAMPLE_TEXTURE2D(_PackedMap, sampler_PackedMap, IN.uvPacked);

                half3 normalTS = UnpackNormal(
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, TRANSFORM_TEX(IN.uvMain, _NormalMap))
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

                half3 viewDirWS =
                    GetWorldSpaceNormalizeViewDir(IN.positionWS);

                // Edge highlight
                half rim = 1.0h - saturate(dot(viewDirWS, normalWS));
                half3 edgeHighlight = SAMPLE_TEXTURE2D(
                    _Ramp, sampler_Ramp, float2(pow(rim, 0.5), 0.5)
                ).rgb * packed.b;

                // Inner structure parallax
                half3 innerStructure = half3(0, 0, 0);
                float2 uv = IN.uvPacked;
                float steps = max(_numSteps, 1.0);
                float stepSize = _marchDistance / steps;

                // View direction expressed in tangent space for UV offset
                half3 viewDirTS = TransformWorldToTangent(
                    viewDirWS,
                    half3x3(IN.tangentWS.xyz, bitangentWS, IN.normalWS)
                );

                [loop]
                for (int i = 0; i < (int)steps; i++)
                {
                    float d = i * stepSize;
                    uv -= (viewDirTS.xy * d / steps) * packed.r;

                    half density = SAMPLE_TEXTURE2D(
                        _PackedMap, sampler_PackedMap, uv
                    ).r;

                    half rampU = (1.0h / steps) * (i + 1);

                    innerStructure += saturate(density) *
                        SAMPLE_TEXTURE2D(
                            _Ramp2, sampler_Ramp2, float2(rampU, 0.5)
                        ).rgb;
                }

                half glowPulse =
                    lerp(_glowMin, _glowMax, sin(_Time.y * _glowFrequency))
                    + _glowMax;

                half3 innerColor =
                    innerStructure * packed.a * _Color.rgb * glowPulse;

                // Preserve original behavior: effects are added to albedo,
                // not emitted light.
                half3 finalAlbedo =
                    albedoSample.rgb + edgeHighlight + innerColor;

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = finalAlbedo;
                surfaceData.metallic = metallicSmooth.r;
                surfaceData.smoothness = metallicSmooth.a;
                surfaceData.normalTS = normalTS;
                surfaceData.occlusion = 1.0h;
                surfaceData.emission = 0;
                surfaceData.alpha = 1.0h;

                InputData inputData = (InputData)0;
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = viewDirWS;
                inputData.shadowCoord =
                    TransformWorldToShadowCoord(IN.positionWS);
                inputData.fogCoord = IN.fogFactor;
                inputData.vertexLighting = half3(0, 0, 0);
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
