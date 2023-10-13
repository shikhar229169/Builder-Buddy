// make HTTP request
const url = `https://api.scorer.gitcoin.co/registry/score/${args[0]}/${args[1]}`

const request = Functions.makeHttpRequest({
  url: url,
  headers: {
    'Content-Type': 'application/json',
    'X-API-KEY': secrets.GC_API_KEY
  }
})

// Execute the API request (Promise)
const response = await request
if (response.error) {
  throw Error("Request failed")
}

const data = response["data"]

if (data.Response === "Error") {
  throw Error(`Api Request Failed`)
}


return Functions.encodeUint256(data.score * 100)
