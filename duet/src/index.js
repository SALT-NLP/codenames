import './main.css';
import { Elm } from './Main.elm';

function makeid(length) {
  var result           = '';
  var characters       = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  var charactersLength = characters.length;
  for ( var i = 0; i < length; i++ ) {
    result += characters.charAt(Math.floor(Math.random() * charactersLength));
  }
  return result;
}

// Metadata about the user is persisted in local storage.
// If there is no user in local storage, we generate one
// with a random player ID and random guest name.
const VERSION = "0.4"

var encodedUser = localStorage.getItem('user');
var lastVersion = localStorage.getItem('version');
var guestNumber = localStorage.getItem('guestNumber');
var parsedUser = encodedUser ? JSON.parse(encodedUser) : null;

if (parsedUser == null || !parsedUser.player_id || 
    !parsedUser.name || lastVersion != VERSION) {
    // generate a new user with a random identifier and save it.
    localStorage.removeItem('user')
    localStorage.removeItem('version')

    var entropy = new Uint32Array(4); // 128 bits
    window.crypto.getRandomValues(entropy);
    var playerID = entropy.join("-");

    if (!guestNumber) {
      guestNumber = makeid(5);
      localStorage.setItem("guestNumber", guestNumber)
    }
    
    parsedUser = {
      player_id: playerID,
      name: 'Guest ' + guestNumber,
    };

    const form = document.getElementById('form');
    form.addEventListener('submit', logSubmit);

} else startElmApp();

function logSubmit(e) {
  e.preventDefault();

  var age = document.getElementById("age-field").value
  var gender = document.getElementById("gender-field").value
  var country = document.getElementById("country-field").value
  var native_speaker = document.getElementById("english-native").checked;

  if ((age == null || String(age).trim().valueOf() == "" || (Number.isInteger(Number(age)) && Number(age) > 0)) && (gender == null || String(gender).trim().valueOf() == "" || /^[A-Za-z\s]*$/.test(String(gender).trim())) && country != null && String(country).trim().valueOf() != "" && /^[A-Za-z\s]*$/.test(String(country).trim())) {
    parsedUser["age"] = age;
    parsedUser["gender"] = gender;
    parsedUser["country"] = country;
    parsedUser["native_speaker"] = native_speaker
    encodedUser = JSON.stringify(parsedUser)
    localStorage.setItem("version", VERSION);
    localStorage.setItem('user', encodedUser);
    startElmApp();
  }
  
}

function startElmApp() { 
  var app = Elm.Main.init({
    node: document.getElementById('root'),
    flags: encodedUser,
  });
  
  app.ports.reloadJS.subscribe(function(data) {
    localStorage.removeItem('user')
    localStorage.removeItem('version')
    window.location.reload();
  });
}

