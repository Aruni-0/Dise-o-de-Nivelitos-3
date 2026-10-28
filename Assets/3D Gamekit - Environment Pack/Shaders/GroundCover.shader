
Shader "Custom/GroundCover_URP"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo", 2D) = "white" {}

        [NoScaleOffset] _MetallicSmooth ("Metallic / Smoothness", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0

        [NoScaleOffset] _Normal ("Normal", 2D) = "bump" {}
        _NormalScale ("Normal Scale", Float) = 1.0

        [NoScaleOffset] _Occlusion ("Occlusion", 2D) = "white" {}
        _OcclusionScale ("Occlusion Scale", Range(0,1)) = 1.0

        [NoScaleOffset] _WindNoise ("Wind Noise", 2D) = "white" {}
        _NoiseAmount ("Noise Amount (XYZ)", Vector) = (0,0,0,0)
        _NoiseScale ("Noise Texture Scale", Float) = 1.0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "TransparentCutout"
            "Queue" = "AlphaTest"
        }

        LOD 300
        Cull Off

        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);

        TEXTURE2D(_Normal);
        SAMPLER(sampler_Normal);

        TEXTURE2D(_MetallicSmooth);
        SAMPLER(sampler_MetallicSmooth);

        TEXTURE2D(_Occlusion);
        SAMPLER(sampler_Occlusion);

        TEXTURE2D(_WindNoise);
        SAMPLER(sampler_WindNoise);

        CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            float4 _MainTex_ST;
            float4 _NoiseAmount;

            half _Glossiness;
            half _Metallic;
            half _NormalScale;
            half _OcclusionScale;
            half _NoiseScale;
        CBUFFER_END

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
            float4 tangentOS : TANGENT;
            float2 uv : TEXCOORD0;
            half4 color : COLOR;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float3 positionWS : TEXCOORD0;
            half3 normalWS : TEXCOORD1;
            half4 tangentWS : TEXCOORD2;
            float2 uv : TEXCOORD3;
            half4 color : TEXCOORD4;
            half fogFactor : TEXCOORD5;
            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord : TEXCOORD6;
            #endif
            UNITY_VERTEX_INPUT_INSTANCE_ID
            UNITY_VERTEX_OUTPUT_STEREO
        };

        float3 ApplyWind(float3 positionOS, float3 positionWS, half4 vertexColor)
        {
            float2 windUV = positionWS.xz + _Time.y * 2.0;

            half3 windNoise = SAMPLE_TEXTURE2D_LOD(
                _WindNoise,
                sampler_WindNoise,
                windUV * _NoiseScale,
                0
            ).rgb;

            half sway20 = sin(_Time.y * 20.0);
            half sway15 = sin(_Time.y * 15.0);
            half sway25 = sin(_Time.y * 25.0);

            positionOS.z += sway20 * vertexColor.a * _NoiseAmount.z * vertexColor.r * windNoise.g;
            positionOS.z += sway15 * vertexColor.a * _NoiseAmount.z * vertexColor.g * windNoise.g;
            positionOS.z += sway25 * vertexColor.a * _NoiseAmount.z * vertexColor.b * windNoise.g;

            positionOS.x += sway20 * vertexColor.a * _NoiseAmount.x * vertexColor.r * windNoise.r;
            positionOS.x += sway15 * vertexColor.a * _NoiseAmount.x * vertexColor.g * windNoise.r;
            positionOS.x += sway25 * vertexColor.a * _NoiseAmount.x * vertexColor.b * windNoise.r;

            positionOS.y += windNoise.r * _NoiseAmount.y * vertexColor.a * vertexColor.r;
            positionOS.y += windNoise.g * _NoiseAmount.y * vertexColor.a * vertexColor.g;
            positionOS.y += windNoise.b * _NoiseAmount.y * vertexColor.a * vertexColor.b;

            return positionOS;
        }

        Varyings Vert(Attributes IN)
        {
            Varyings OUT = (Varyings)0;

            UNITY_SETUP_INSTANCE_ID(IN);
            UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

            float3 originalPositionWS = TransformObjectToWorld(IN.positionOS.xyz);
            float3 deformedOS = ApplyWind(IN.positionOS.xyz, originalPositionWS, IN.color);

            VertexPositionInputs pos = GetVertexPositionInputs(deformedOS);
            VertexNormalInputs norm = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

            OUT.positionCS = pos.positionCS;
            OUT.positionWS = pos.positionWS;
            OUT.normalWS = norm.normalWS;
            OUT.tangentWS = half4(norm.tangentWS, IN.tangentOS.w * GetOddNegativeScale());
            OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
            OUT.color = IN.color;
            OUT.fogFactor = ComputeFogFactor(pos.positionCS.z);

            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                OUT.shadowCoord = GetShadowCoord(pos);
            #endif

            return OUT;
        }

        half4 SampleAlbedo(float2 uv, float3 positionWS)
        {
            half4 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);

            half4 noiseTex = SAMPLE_TEXTURE2D(
                _WindNoise,
                sampler_WindNoise,
                positionWS.xz * 0.1
            );

            c.rgb *= lerp(_Color.rgb, half3(1,1,1), noiseTex.rgb);
            c.a *= _Color.a;

            return c;
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
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            half4 Frag(Varyings IN, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                half4 albedo = SampleAlbedo(IN.uv, IN.positionWS);

                clip(albedo.a - 0.5h);

                half4 metallicSmooth = SAMPLE_TEXTURE2D(
                    _MetallicSmooth, sampler_MetallicSmooth, IN.uv
                );

                half occlusionSample = SAMPLE_TEXTURE2D(
                    _Occlusion, sampler_Occlusion, IN.uv
                ).g;

                half3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_Normal, sampler_Normal, IN.uv),
                    _NormalScale
                );

                half3 normalWS = normalize(IN.normalWS);
                half3 tangentWS = normalize(IN.tangentWS.xyz);
                half3 bitangentWS = normalize(
                    cross(normalWS, tangentWS) * IN.tangentWS.w
                );

                half3x3 tangentToWorld = half3x3(
                    tangentWS, bitangentWS, normalWS
                );

                normalWS = normalize(
                    TransformTangentToWorld(normalTS, tangentToWorld)
                );

                // Vegetation can be viewed from either side.
                if (!IS_FRONT_VFACE(face, true, false))
                {
                    normalWS = -normalWS;
                }

                InputData inputData = (InputData)0;
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);

                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    inputData.shadowCoord = IN.shadowCoord;
                #else
                    inputData.shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                #endif

                inputData.fogCoord = IN.fogFactor;
                inputData.vertexLighting = half3(0,0,0);
                inputData.bakedGI = SampleSH(normalWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);
                inputData.shadowMask = half4(1,1,1,1);

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedo.rgb;
                surfaceData.metallic = _Metallic * metallicSmooth.r;
                surfaceData.specular = half3(0,0,0);
                surfaceData.smoothness = _Glossiness * metallicSmooth.a;
                surfaceData.normalTS = normalTS;
                surfaceData.emission = half3(0,0,0);
                surfaceData.occlusion = lerp(1.0h, occlusionSample, _OcclusionScale);
                surfaceData.alpha = albedo.a;
                surfaceData.clearCoatMask = 0;
                surfaceData.clearCoatSmoothness = 0;

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

            #pragma target 3.5
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #pragma multi_compile_instancing

            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            ShadowVaryings ShadowVert(Attributes IN)
            {
                ShadowVaryings OUT = (ShadowVaryings)0;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                float3 originalPositionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 deformedOS = ApplyWind(IN.positionOS.xyz, originalPositionWS, IN.color);

                float3 positionWS = TransformObjectToWorld(deformedOS);
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);

                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                OUT.positionCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, normalWS, lightDirectionWS)
                );

                #if UNITY_REVERSED_Z
                    OUT.positionCS.z = min(OUT.positionCS.z, OUT.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    OUT.positionCS.z = max(OUT.positionCS.z, OUT.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.positionWS = positionWS;

                return OUT;
            }

            half4 ShadowFrag(ShadowVaryings IN) : SV_Target
            {
                half4 albedo = SampleAlbedo(IN.uv, IN.positionWS);
                clip(albedo.a - 0.5h);
                return 0;
            }

            ENDHLSL
        }
    }

    FallBack Off
}
