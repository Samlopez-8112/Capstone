import requests

url = "https://crimeometer.p.rapidapi.comstats/"

headers = {
	"x-rapidapi-key": "53922cf159mshbad899056ff82ccp1ca1b5jsn9df968f207e7",
	"x-rapidapi-host": "crimeometer.p.rapidapi.com",
	"x-api-key": "k3RAzKN1Ag14xTPlculT39RZb38LGgsG8n27ZycG"
}

response = requests.get(url, headers=headers)

print(response.json())