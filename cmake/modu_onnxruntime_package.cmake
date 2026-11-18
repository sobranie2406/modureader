include(FetchContent)
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()

set(MODU_ORT_VERSION 1.22.0)
set(MODU_ORT_NUGET_URL "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${MODU_ORT_VERSION}/microsoft.ml.onnxruntime.${MODU_ORT_VERSION}.nupkg")
set(MODU_ORT_NUGET_SHA256 "d571e63a2329baacb713f441e65ad75284de354db6e1ac435fe4bebbb417986a")

# The CPU NuGet package supplies upstream native libraries for both desktop
# architectures without depending on GitHub's release download endpoints.
FetchContent_Declare(modu_ort
  URL "${MODU_ORT_NUGET_URL}"
  URL_HASH "SHA256=${MODU_ORT_NUGET_SHA256}"
  DOWNLOAD_NAME "microsoft.ml.onnxruntime.${MODU_ORT_VERSION}.zip"
  TLS_VERIFY ON)
FetchContent_MakeAvailable(modu_ort)
