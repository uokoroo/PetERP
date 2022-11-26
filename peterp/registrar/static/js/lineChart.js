var ctxL = document.getElementById("lineChart").getContext("2d");
var myLineChart = new Chart(ctxL, {
  type: "line",
  data: {
    labels: [
      "Fall 2019",
      "Spring 2020",
      "Fall 2020",
      "Spring 2021",
      "Fall 2021",
    ],
    datasets: [
      {
        label: "Overrides",
        data: [65, 59, 80, 81, 56, 55, 40],
        backgroundColor: ["rgba(105, 0, 132, .2)"],
        borderColor: ["rgba(200, 99, 132, .7)"],
        borderWidth: 2,
      },
      {
        label: "Overloads",
        data: [28, 48, 40, 19, 86, 27, 90],
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
