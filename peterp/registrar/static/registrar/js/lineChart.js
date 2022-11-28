var ctxL = document.getElementById("lineChart").getContext("2d");

const override_data = JSON.parse(document.getElementById('override_data').textContent);
const overloads = JSON.parse(document.getElementById('overloads').textContent);
const sessions = JSON.parse(document.getElementById('sessions').textContent);
// let labelsTrans = Object.keys(overloads).map(getSession());
function getSession() {
  let data_new = [];
  for (session in Object.keys(overloads)) {
    data_new.push(sessions[session].semester + ' ' + sessions[session].year);
  }
  return data_new;
};
let labels = getSession();
var myLineChart = new Chart(ctxL, {
  type: "line",
  data: {
    labels: labels,
    datasets: [
      {
        label: "Overrides",
        data: Object.values(override_data),
        backgroundColor: ["rgba(105, 0, 132, .2)"],
        borderColor: ["rgba(200, 99, 132, .7)"],
        borderWidth: 2,
      },
      {
        label: "Overloads",
        data: Object.values(overloads),
        backgroundColor: ["rgba(0, 137, 132, .2)"],
        borderColor: ["rgba(0, 10, 130, .7)"],
        borderWidth: 2,
      },
    ],
  },
  options: {
    responsive: true,
  },
});
