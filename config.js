config = {
    logLevel : 'debug', //Use 'debug' just to check if everything is working. Otherwise use 'info'

    emailServer : { // To configure this see https://github.com/andris9/Nodemailer
        type: 'SMTP',
        parameters: {
            service: "Gmail",
            auth: {
              user: "yourEmail@gmail.com",
              pass: "yourPassword"
            }
        }
    },

    slackWebhook : [
      'https://hooks.slack.com/services/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',
      'https://hooks.slack.com/services/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' 
    ],
    slackOpts : {
      prefix : "<!group> <https://techcrunch.com/event-info/disrupt-sf-2016/disrupt-sf-hackathon-2016/#pg-1238703-6 | Get the TC Hackathon tickets here>",
      extra : {
        username : "Scraper Notifier",
        icon_url : "http://images.all-free-download.com/images/graphiclarge/scraper_37742.jpg"
      }
    },

    //It can be the same email in emailServer
    //toEmail: "notifyToThisEmail@gmail.com",

    //Should I report errors reading the URLs? Useful in case the IP get blacklisted or for server problems.
    notifyErrors : true,

    rules: [
        //You can add another rule for another URL
        {url: "https://www.universe.com/api/v1/listings/57a3a2d9a1f7af003c95499c.json", //URL to scrape
         //You can even use
         //  when: function (body, rule) {//return true when you want to be notified }
         when: [{
            notExist: '"count_available":null',
         }],
         frequency: 5 * 60 * 1000
        }
    ]
};

module.exports = config;

console.log ("Loading config from config.js");
