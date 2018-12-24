require 'bundler/setup'
require 'yaml'
require 'mastodon'
require 'ikku'
require 'sanitize'

config = YAML.load_file("./key.yml")
debug = true
unfollow_str = "フォロー解除"

stream = Mastodon::Streaming::Client.new(
  base_url: "https://" + config["base_url"],
  bearer_token: config["access_token"])

rest = Mastodon::REST::Client.new(
  base_url: "https://" + config["base_url"],
  bearer_token: config["access_token"])

#eviewer = Ikku::Reviewer.new(rule:[4, 4, 5])
reviewer = Ikku::Reviewer.new(rule:[8, 5])

reviewer_id = rest.verify_credentials().id

begin
  stream.user() do |toot|
    if toot.kind_of?(Mastodon::Status) then
      content = Sanitize.clean(toot.content)
      unfollow_request = false
      toot.mentions.each do |mention|
        if mention.id == reviewer_id
          if !content.index(unfollow_str).nil?
            unfollow_request = true
            relationships = rest.relationships([toot.account.id])
            relationships.each do |relationship|
              if relationship.following?
                rest.unfollow(toot.account.id)
                p "unfollow"
              end
            end
          end
        end
      end
      if !unfollow_request && (toot.visibility == "public" || toot.visibility == "unlisted") then
        if toot.in_reply_to_id.nil? && toot.attributes["reblog"].nil? then
          p "@#{toot.account.acct}: #{content}" if debug
          haiku = reviewer.find(content)
          if haiku then
            #postcontent = "『#{haiku.phrases[0].join("")}#{haiku.phrases[1].join("")}#{haiku.phrases[2].join("")}』"
            postcontent = "『#{haiku.phrases[0].join("")}#{haiku.phrases[1].join("")}』"
            p "俳句検知: #{postcontent}" if debug
            #公開投稿にはタグをつける(BOSSのLTLに流す)
            if toot.attributes["tags"].map{|t| t["name"]}.include?("theboss_tech") then
              postcontent += " #theboss_tech"
            end
            #CWにはCW付きで返す
            if toot.attributes["spoiler_text"].empty? then
              rest.create_status("@#{toot.account.acct} " + postcontent + "\nはい！はい！はいはいはい！あるある探検隊！あるある探検隊！", toot.id)
            else
              rest.create_status("@#{toot.account.acct}\n" + postcontent, in_reply_to_id: toot.id, spoiler_text: "はい！はい！はいはいはい！あるある探検隊！あるある探検隊！")
            end
            p "post!" if debug
          elsif content.include?("気絶") then
            postcontent2 = ""
            if toot.attributes["tags"].map{|t| t["name"]}.include?("theboss_tech") then
              postcontent2 += " #theboss_tech"
            rest.create_status("@#{toot.account.acct} \nあかん、気絶してもうた！こうなったらあるあるさんとこの探検隊呼ぶしかない！" + postcontent2, toot.id)
          elsif debug
            p "俳句なし"
          end
        elsif debug
          p "BT or reply"
        end
      elsif debug
        p "private toot"
      end
    elsif toot.kind_of?(Mastodon::Notification) then
      p "#{toot.type} by #{toot.account.id}" if debug
      rest.follow(toot.account.id) if toot.type == "follow"
    end
  end
rescue => e
  p "error"
  puts e
  retry
end
