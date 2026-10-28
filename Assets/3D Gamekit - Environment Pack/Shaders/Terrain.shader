
Shader "Custom/Terrain_URP"
{
    Properties
    {
        _WaterColor ("Water Color", Color) = (1,1,1,1)
        _WaterEdge ("Water Edge Hardness", Range(0,1)) = 0.2
        [NoScaleOffset] _WaterRoughness ("Water Roughness", 2D) = "white" {}
        _ParallaxStrength ("Parallax Strength", Range(0,0.1)) = 0.05

        [NoScaleOffset] _Albedo01 ("Albedo 01", 2D) = "white" {}
        [NoScaleOffset] _Normal01 ("Normal 01", 2D) = "bump" {}
        [NoScaleOffset] _MRHAO01 ("Metal/Rough/Height/AO 01", 2D) = "white" {}
        _TextureScale01 ("Texture Scale 01", Float) = 1
        _Falloff01 ("Blend Falloff 01", Range(0,1)) = 0.2

        [NoScaleOffset] _Albedo02 ("Albedo 02", 2D) = "white" {}
        [NoScaleOffset] _Normal02 ("Normal 02", 2D) = "bump" {}
        [NoScaleOffset] _Normal02Detail ("Normal 02 Detail", 2D) = "bump" {}
        [NoScaleOffset] _MRHAO02 ("Metal/Rough/Height/AO 02", 2D) = "white" {}
        _TextureScale02 ("Texture Scale 02", Float) = 1
        _Falloff02 ("Blend Falloff 02", Range(0,1)) = 0.2

        [NoScaleOffset] _Albedo03 ("Albedo 03", 2D) = "white" {}
        [NoScaleOffset] _Normal03 ("Normal 03", 2D) = "bump" {}
        [NoScaleOffset] _MRHAO03 ("Metal/Rough/Height/AO 03", 2D) = "white" {}
        _TextureScale03 ("Texture Scale 03", Float) = 1
        _Falloff03 ("Blend Falloff 03", Range(0,1)) = 0.2
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

        TEXTURE2D(_Albedo01);
        SAMPLER(sampler_Albedo01);
        TEXTURE2D(_Albedo02);
        SAMPLER(sampler_Albedo02);
        TEXTURE2D(_Albedo03);
        SAMPLER(sampler_Albedo03);

        TEXTURE2D(_Normal01);
        SAMPLER(sampler_Normal01);
        TEXTURE2D(_Normal02);
        SAMPLER(sampler_Normal02);
        TEXTURE2D(_Normal02Detail);
        SAMPLER(sampler_Normal02Detail);
        TEXTURE2D(_Normal03);
        SAMPLER(sampler_Normal03);

        TEXTURE2D(_MRHAO01);
        SAMPLER(sampler_MRHAO01);
        TEXTURE2D(_MRHAO02);
        SAMPLER(sampler_MRHAO02);
        TEXTURE2D(_MRHAO03);
        SAMPLER(sampler_MRHAO03);

        TEXTURE2D(_WaterRoughness);
        SAMPLER(sampler_WaterRoughness);

        CBUFFER_START(UnityPerMaterial)
            half4 _WaterColor;
            half _WaterEdge;
            half _ParallaxStrength;
            half _TextureScale01;
            half _TextureScale02;
            half _TextureScale03;
            half _Falloff01;
            half _Falloff02;
            half _Falloff03;
        CBUFFER_END

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
            float4 tangentOS : TANGENT;
            float2 uv : TEXCOORD0;
            float4 color : COLOR;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float3 positionWS : TEXCOORD0;
            half3 normalWS : TEXCOORD1;
            half4 tangentWS : TEXCOORD2;
            float4 color : TEXCOORD3;
            half3 viewDirWS : TEXCOORD4;
            half fogFactor : TEXCOORD5;
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
            OUT.color = IN.color;
            OUT.viewDirWS = GetWorldSpaceNormalizeViewDir(pos.positionWS);
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
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            half4 Frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                float2 uv = IN.positionWS.xz;

                // View-dependent UV displacement, approximating the
                // original parallax effect using world-space view direction.
                half viewZ = max(abs(IN.viewDirWS.y), 0.15h);
                float2 parallaxOffset =
                    IN.viewDirWS.xz / viewZ * _ParallaxStrength;

                // Layer 1
                half4 a01 = SAMPLE_TEXTURE2D(
                    _Albedo01, sampler_Albedo01,
                    uv * _TextureScale01
                );

                // Vertex red controls the first transition.
                half blend01 = smoothstep(
                    IN.color.r - max(_Falloff01, 0.001h),
                    IN.color.r,
                    1.0h - a01.a
                );

                float2 uv02 =
                    (uv + parallaxOffset * blend01) * _TextureScale02;

                half4 a02 = SAMPLE_TEXTURE2D(
                    _Albedo02, sampler_Albedo02, uv02
                );

                // Vertex green controls the second transition.
                half blend02 = smoothstep(
                    IN.color.g - max(_Falloff02, 0.001h),
                    IN.color.g,
                    1.0h - a02.a
                );

                half4 a03 = SAMPLE_TEXTURE2D(
                    _Albedo03, sampler_Albedo03,
                    uv * _TextureScale03
                );

                half3 albedo = lerp(a01.rgb, a02.rgb, blend01);
                albedo = lerp(albedo, a03.rgb, blend02);

                // Normal maps
                half3 n01 = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _Normal01, sampler_Normal01,
                        uv * _TextureScale01
                    )
                );

                half3 n02 = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _Normal02, sampler_Normal02, uv02
                    )
                );

                half3 n03 = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _Normal03, sampler_Normal03,
                        uv * _TextureScale03
                    )
                );

                half3 n02Detail = UnpackNormal(
                    SAMPLE_TEXTURE2D(
                        _Normal02Detail, sampler_Normal02Detail,
                        uv * 0.1
                    )
                );

                n02 = normalize(BlendRNM(n02, n02Detail));

                half3 normalTS = normalize(lerp(n01, n02, blend01));
                normalTS = normalize(lerp(normalTS, n03, blend02));

                // Transform the blended top-down normal into world space.
                // Texture X/Y correspond to world X/Z.
                half3 topNormalWS = normalize(
                    half3(normalTS.x, normalTS.z, normalTS.y)
                );

                // Reorient to the terrain's geometric normal.
                half3 geomNormal = normalize(IN.normalWS);
                half3 reorientedNormal = normalize(
                    BlendRNM(
                        half3(geomNormal.x, geomNormal.z,
                              max(abs(geomNormal.y), 0.01h)),
                        normalTS
                    )
                );

                topNormalWS = normalize(
                    half3(
                        reorientedNormal.x,
                        reorientedNormal.z,
                        reorientedNormal.y
                    )
                );

                half3 tangentWS = normalize(IN.tangentWS.xyz);
                half3 bitangentWS = normalize(
                    cross(geomNormal, tangentWS) * IN.tangentWS.w
                );

                half3x3 tangentToWorld = half3x3(
                    tangentWS, bitangentWS, geomNormal
                );

                half3 baseNormalWS = normalize(
                    TransformTangentToWorld(normalTS, tangentToWorld)
                );

                half3 finalNormalWS = normalize(
                    lerp(baseNormalWS, topNormalWS, 0.5h)
                );

                // Packed maps: R = metallic, G = roughness,
                // B = height, A = ambient occlusion.
                // The original uses A for its smoothness calculations.
                half4 mr01 = SAMPLE_TEXTURE2D(
                    _MRHAO01, sampler_MRHAO01,
                    uv * _TextureScale01
                );

                half4 mr02 = SAMPLE_TEXTURE2D(
                    _MRHAO02, sampler_MRHAO02, uv02
                );

                half4 mr03 = SAMPLE_TEXTURE2D(
                    _MRHAO03, sampler_MRHAO03,
                    uv * _TextureScale03
                );

                half smoothness = lerp(0.3h, mr02.a, blend01);
                smoothness = lerp(smoothness, mr03.a, blend02);

                // Water layer controlled by vertex alpha.
                half waterMask = smoothstep(
                    IN.color.a,
                    IN.color.a + max(_WaterEdge, 0.001h),
                    1.0h - a01.a
                );

                albedo = lerp(
                    albedo * _WaterColor.rgb,
                    albedo,
                    waterMask
                );

                half waterSmoothness = SAMPLE_TEXTURE2D(
                    _WaterRoughness, sampler_WaterRoughness,
                    uv * 0.3
                ).a * 0.95h;

                smoothness = lerp(
                    waterSmoothness, smoothness, waterMask
                );

                half metallic = lerp(
                    mr01.r, mr02.r, blend01
                );
                metallic = lerp(metallic, mr03.r, blend02);

                // URP PBR
                InputData inputData = (InputData)0;
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = finalNormalWS;
                inputData.viewDirectionWS = normalize(IN.viewDirWS);
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
                surfaceData.smoothness = saturate(smoothness);
                surfaceData.normalTS = normalTS;
                surfaceData.emission = half3(0,0,0);
                surfaceData.occlusion = 1.0h;
                surfaceData.alpha = 1.0h;
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

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }

    FallBack Off
}
