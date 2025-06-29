#!/bin/bash
set -e

RESOURCE_GROUP="my-gallery-rg"
LOCATION="japaneast"
STORAGE_ACCOUNT="mygallery$RANDOM"
CONTAINER_NAME="images"
WEB_DIR="./site"
JS_FILE="$WEB_DIR/scripts/gallery.js"
TMP_JS_FILE="$WEB_DIR/scripts/gallery.generated.js"

# リソースグループの作成
echo "⏳ Azure リソースグループを作成中..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# ARMテンプレートでストレージアカウントとコンテナを作成
echo "⏳ ARM テンプレートを使ってストレージアカウントと BLOB コンテナを作成中..."
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file template.json \
  --parameters storageAccountName=$STORAGE_ACCOUNT containerName=$CONTAINER_NAME \
  --output none

# 静的 Web サイト機能を有効化
echo "⏳ ストレージアカウントに静的 Web サイト機能を有効化中..."
az storage blob service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --static-website \
  --index-document index.html \
  --404-document index.html

# 機能が有効になるまでリトライしながら確認
echo "⏳ 静的 Web サイト機能の有効化確認中..."
MAX_RETRIES=10
for i in $(seq 1 $MAX_RETRIES); do
    ENABLED=$(az storage blob service-properties show \
        --account-name $STORAGE_ACCOUNT \
        --query "staticWebsite.enabled" -o tsv 2>/dev/null || echo "false")

    if [ "$ENABLED" == "true" ]; then
        echo "✅ 静的 Web サイトが有効になりました"
        break
    else
        echo "🔁 有効化を待機中... (${i}/${MAX_RETRIES})"
        sleep 5
    fi
done

# 現在のユーザー ID を取得し、ストレージアカウントに RBAC ロールを付与
echo "⏳ ユーザー ID の取得と RBAC 権限の設定中..."
USER_ID=$(az ad signed-in-user show --query id -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
STORAGE_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"

az role assignment create \
  --assignee $USER_ID \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_SCOPE || true

# RBAC 設定が有効になるまでアクセスチェックをリトライ
echo "⏳ RBAC の反映を確認中（最大10回リトライ）..."
for i in $(seq 1 10); do
    if az storage container show \
      --name $CONTAINER_NAME \
      --account-name $STORAGE_ACCOUNT \
      --auth-mode login >/dev/null 2>&1; then
        echo "✅ BLOB コンテナにアクセスできました"
        break
    else
        echo "🔁 RBAC 反映待ち (${i}/10)"
        sleep 5
    fi
done

# 一時的に使う SAS トークンを生成
echo "⏳ SAS トークンを生成中..."
if date -d "next day" >/dev/null 2>&1; then
    EXPIRY=$(date -u -d "next day" '+%Y-%m-%dT%H:%MZ')
elif date -v+1d >/dev/null 2>&1; then
    EXPIRY=$(date -v+1d -u '+%Y-%m-%dT%H:%MZ')
else
    echo "❌ 日付の計算に失敗しました"
    exit 1
fi

SAS_TOKEN=$(az storage container generate-sas \
    --account-name $STORAGE_ACCOUNT \
    --name $CONTAINER_NAME \
    --permissions rlw \
    --expiry $EXPIRY \
    --auth-mode login \
    --as-user \
    --output tsv)
SAS_TOKEN="?$SAS_TOKEN"
ESCAPED_SAS_TOKEN=$(printf '%s\n' "$SAS_TOKEN" | sed -e 's/[&/\]/\\&/g')

# gallery.js のテンプレートを加工して一時ファイルを生成
echo "⏳ gallery.js を加工して一時ファイルを作成中..."
cp "$JS_FILE" "$TMP_JS_FILE"
if sed --version >/dev/null 2>&1; then
    # Linux の GNU sed
    sed -i \
        -e "s|__STORAGE_ACCOUNT__|$STORAGE_ACCOUNT|g" \
        -e "s|__SAS_TOKEN__|$ESCAPED_SAS_TOKEN|g" "$TMP_JS_FILE"
else
    # macOS の BSD sed
    sed -i '' \
        -e "s|__STORAGE_ACCOUNT__|$STORAGE_ACCOUNT|g" \
        -e "s|__SAS_TOKEN__|$ESCAPED_SAS_TOKEN|g" "$TMP_JS_FILE"
fi

# 元のJSファイルをバックアップし、加工済みファイルで上書き
mv "$JS_FILE" "${JS_FILE}.orig"
mv "$TMP_JS_FILE" "$JS_FILE"

# Web サイトのファイルを一括アップロード
echo "⏳ Web サイトのファイルを Azure Storage にアップロード中..."
az storage blob upload-batch \
    --source $WEB_DIR \
    --destination \$web \
    --account-name $STORAGE_ACCOUNT \
    --overwrite

# index.html を明示的に上書きアップロード（順番を保証）
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name \$web \
    --name index.html \
    --file "$WEB_DIR/index.html" \
    --overwrite

# JS を元に戻す
mv "${JS_FILE}.orig" "$JS_FILE"

# デプロイ完了、Web サイト URL を表示
ENDPOINT=$(az storage account show \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query "primaryEndpoints.web" -o tsv)

echo ""
echo "✅ デプロイが完了しました"
echo "🔗 公開 URL: $ENDPOINT"
echo "📂 コンテナ名: $CONTAINER_NAME"
echo "🪪 SAS トークンの有効期限: $EXPIRY"
