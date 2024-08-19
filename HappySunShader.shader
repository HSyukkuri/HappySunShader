Shader "Unlit/HappyToonShader_v20240304"
{
    Properties
    {
        [NoScaleOffset]_MainTex ("Color map", 2D) = "white" {}
        [NoScaleOffset]_NormalMap ("Normal map", 2D) = "bump" {}
         [Header(Shadow_Light)]
        _ShadowPower("影の強さ",Range(0,1)) = 0.5
        _ShadowBlur("影のぼかし",Range(0,1)) = 0.3
        _ShadowColor("影の色",Color) = (1,1,1,1)
         [NoScaleOffset]_ShadowMask("影マスク（黒い所に追加の影）",2D) = "white"{}

        _RimLight("リムライトの強さ",Range(0,1)) = 0.02
        _RimLightBlur("リムライトのぼかし",Range(0,1)) = 0.02
        _RimLightColor("リムライトの色",Color) = (1,1,1,1)
         [NoScaleOffset]_ShadowRemoveMask("影除外マスク（白い所は影の影響を無視）",2D) = "black"{}
        [Header(Outline)]
        _OutLineColor("輪郭線の色",Color) = (0,0,0,1)
        _OutlineThick("輪郭線の太さ",float) = 0.5
         [NoScaleOffset]_OutLineMask("輪郭線マスク（白い所ほど太い）",2D) = "white"{}
        [Header(Dither)]
        _DitherLevel("ディザレベル", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
        }
        LOD 100
        

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_ShadowMask);
        SAMPLER(sampler_ShadowMask);
        TEXTURE2D(_OutLineMask);
        SAMPLER(sampler_OutLineMask);
        TEXTURE2D(_ShadowRemoveMask);
        SAMPLER(sampler_ShadowRemoveMask);
        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);



        CBUFFER_START(UnityPerMaterial)
        float4 _MainTex_ST;
        half _ShadowPower;
        half _ShadowBlur;
        half3 _ShadowColor;
        float _OutlineThick;
        half4 _OutLineColor;
        half _RimLight;
        half _RimLightBlur;
        half3 _RimLightColor;
        //ディザ抜き用のプロパティ
        float _Alpha;
        half _DitherLevel;

            // しきい値マップ
            static const int pattern[16] =
            {
                0,  8,  2, 10,
                12,  4, 14,  6,
                3, 11,  1,  9,
                15,  7, 13,  5
            };

        CBUFFER_END
        ENDHLSL
        
        //メインパス
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog
            
            // Universal Pipeline shadow keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 positionSS : TEXCOORD5;
                float2 uv : TEXCOORD0;
                float fogFactor : TEXCOORD1;
                float3 posWS : TEXCOORD2;
                float3 normalOS : NORMAL;
                float3 normalWS : NORMAL_WS;
                float4 tangentWS : TANGENT_WS;
                float3 viewDir:TEXCOORD3;

            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.fogFactor = ComputeFogFactor(o.vertex.z);
                o.posWS = TransformObjectToWorld(v.vertex.xyz);
                //スクリーン座標上での位置
                o.positionSS = ComputeScreenPos(o.vertex);

                o.normalOS = v.normal;
                // TransformObjectToWorldNormal()でノーマルをオブジェクト空間からワールド空間へ変換して格納
                o.normalWS = TransformObjectToWorldNormal(v.normal);
                // サイン（正弦）とワールド空間のタンジェントの計算
                float sign = v.tangent.w * GetOddNegativeScale();
                VertexNormalInputs vni = GetVertexNormalInputs(v.normal, v.tangent);
                o.tangentWS = float4(vni.tangentWS, sign);
                //o.viewDir = normalize(TransformWorldToObject(GetCameraPositionWS()) - v.vertex.xyz);
                //o.viewDir =GetViewForwardDir();
                o.viewDir = normalize(GetWorldSpaceViewDir(TransformObjectToWorld(v.vertex)));
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // スクリーン座標
                float2 screenPos = i.positionSS.xy / i.positionSS.w;
                // 画面サイズを乗算して、ピクセル単位に
                float2 screenPosInPixel = screenPos.xy * _ScreenParams.xy;
                // ディザリングテクスチャ用のUVを作成
                int ditherUV_x = (int)fmod(screenPosInPixel.x, 4.0f);
                int ditherUV_y = (int)fmod(screenPosInPixel.y, 4.0f);
                float dither = pattern[ditherUV_x+ ditherUV_y * 4];
                // 閾値が0以下なら描画しない
                clip(dither - ((1.0f - _DitherLevel)*16.0f));

                //テクスチャからメインカラーを取得
                float4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                //影計算
                half shadowMask = SAMPLE_TEXTURE2D_LOD(_ShadowMask, sampler_ShadowMask, i.uv, 1.0).r;
                half shadowRemoveMask = SAMPLE_TEXTURE2D_LOD(_ShadowRemoveMask, sampler_ShadowRemoveMask, i.uv, 1.0).r;
                float4 shadowRemoveColor = col * shadowRemoveMask;
                float4 shadowCoord = TransformWorldToShadowCoord(i.posWS);
                Light mainLight = GetMainLight(shadowCoord);
                half shadow = mainLight.shadowAttenuation ;
                //ここで何とかする。(ノーマルマップ反映) 
                float3 normal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap,sampler_NormalMap,i.uv));
                // vert()で算出したサイン（正弦）
                float sgn = i.tangentWS.w;
                // 従法線（bitangent / binormal）を計算
                float3 bitangent = sgn * cross(i.normalWS.xyz, i.tangentWS.xyz);
                // normalize()（正規化）も同時にしておく
                float3 normalWS = normalize(mul(normal, float3x3(i.tangentWS.xyz, bitangent.xyz, i.normalWS.xyz)));
                //反射ベクトルと視線ベクトルの内積を計算
                half d_light = dot(normalWS,mainLight.direction) * 0.5 + 0.5;
                half smoothShadow = smoothstep(_ShadowPower, _ShadowPower+ _ShadowBlur, d_light * shadow);//影０、明１
                smoothShadow = min(smoothShadow,shadowMask);
                //Light addLight0 = GetAdditionalLight(0, i.posWS);
                //shadow *= addLight0.shadowAttenuation;
                col.rgb *= _ShadowColor + smoothShadow - (_ShadowColor * smoothShadow);
                

                //リムライト計算
                half dotNorView = 1.5f - abs(dot(i.viewDir,normalWS));
                half dotLigView = 1.5f - (dot(i.viewDir,mainLight.direction) * 0.5 + 0.5);
                half fresnel = (dotNorView *dotLigView);//暗０、明１
                half fresnelStep = smoothstep(0.5-(_RimLightBlur/2) ,0.5 + (_RimLightBlur/2), fresnel * _RimLight);//影０、明１
                half3 rimLightMap = (fresnelStep * smoothShadow) * _RimLightColor;
                col.rgb = col.rgb + rimLightMap;
                col.rgb *= mainLight.color;
                col.rgb += shadowRemoveColor.rgb;
                col.rgb = MixFog(col.rgb, i.fogFactor);
                //col.rgb = fresnelStep;
                return col;
            }
            ENDHLSL
        }
        //輪郭線パス
        Pass
        {
            Name "Outline"
            Cull Front
            ZWrite On

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment frag
                // make fog work
                #pragma multi_compile_fog
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"


                struct a2v{
                    float4 positionOS: POSITION;
                    float3 normalOS: NORMAL;
                    float4 tangentOS: TANGENT;
                    float2 uv: TEXCOORD0;
                };

                struct v2f{
                    float4 positionCS: SV_POSITION;
                    float4 positionSS: TEXCOORD5;
                    float fogFactor : TEXCOORD1;
                };

                v2f vert(a2v v){
                    v2f o;
                    //クリップスペース上のノーマルを取得
                    VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(v.normalOS,v.tangentOS);
                    float3 normalWS = vertexNormalInput.normalWS;
                    float3 normalCS = TransformWorldToHClipDir(normalWS);

                    //輪郭線マスクの演算
                    half mask = SAMPLE_TEXTURE2D_LOD(_OutLineMask, sampler_OutLineMask, v.uv, 1.0).r;

                    //クリップスペース上でノーマル方向に外側に広げた位置を取得
                    VertexPositionInputs positionInputs = GetVertexPositionInputs(v.positionOS.xyz);
                    o.positionCS = positionInputs.positionCS + float4(normalCS.xy * 0.001 * _OutlineThick * mask,0,0);

                    //フォグ計算
                    o.fogFactor = ComputeFogFactor(o.positionCS.z);

                    //スクリーン座標上での位置
                    o.positionSS = ComputeScreenPos(o.positionCS);
                    return o;
                }

                half4 frag(v2f i):SV_Target{
                    // スクリーン座標
                    float2 screenPos = i.positionSS.xy / i.positionSS.w;
                    // 画面サイズを乗算して、ピクセル単位に
                    float2 screenPosInPixel = screenPos.xy * _ScreenParams.xy;
                    // ディザリングテクスチャ用のUVを作成
                    int ditherUV_x = (int)fmod(screenPosInPixel.x, 4.0f);
                    int ditherUV_y = (int)fmod(screenPosInPixel.y, 4.0f);
                    float dither = pattern[ditherUV_x+ ditherUV_y * 4];
                    // 閾値が0以下なら描画しない
                    clip(dither - ((1.0f - _DitherLevel)*16.0f));
                    
                    float4 col = _OutLineColor;
                    
                    col.rgb = MixFog(_OutLineColor.rgb, i.fogFactor);

                    return col;
                }

            ENDHLSL
        }

        //影パス
        Pass
        {
            Tags { "LightMode"="ShadowCaster" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ShadowsCasterPass.hlsl �ɒ�`����Ă���O���[�o���ȕϐ�
            float3 _LightDirection;
            
            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f {
                float4 pos : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                UNITY_SETUP_INSTANCE_ID(v);
                v2f o;
                // ShadowsCasterPass.hlsl �� GetShadowPositionHClip() ���Q�l��
                float3 positionWS = TransformObjectToWorld(v.vertex.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normal);
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
#if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
#else
                positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
#endif
                o.pos = positionCS;

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                return 0;
            }

            ENDHLSL
        }
    }
}