// MongoDB副本集初始化脚本
// 此脚本在MongoDB容器首次启动时自动执行，用于配置副本集

print("开始初始化MongoDB副本集...");

// 切换到admin数据库进行管理操作
db = db.getSiblingDB('admin');

// 等待MongoDB完全启动
sleep(5000);

try {
    // 检查副本集状态
    var status = rs.status();
    print("副本集已存在，状态: " + status.ok);
} catch (e) {
    print("副本集不存在，开始初始化...");
    
    // 初始化副本集
    var config = {
        _id: "rs0",
        version: 1,
        members: [
            {
                _id: 0,
                host: "ainoval-mongo:27017",
                priority: 1
            }
        ]
    };
    
    var result = rs.initiate(config);
    print("副本集初始化结果: " + JSON.stringify(result));
    
    if (result.ok === 1) {
        print("副本集初始化成功！");
        
        // 等待副本集变为主节点
        print("等待成为主节点...");
        while (true) {
            try {
                var status = rs.status();
                if (status.myState === 1) { // PRIMARY
                    print("已成为主节点");
                    break;
                }
                print("当前状态: " + status.myState + "，等待中...");
                sleep(2000);
            } catch (e) {
                print("等待状态检查: " + e);
                sleep(2000);
            }
        }
        
        // 创建应用数据库和用户（如果需要）
        print("副本集配置完成！");
    } else {
        print("副本集初始化失败: " + JSON.stringify(result));
    }
}

print("MongoDB副本集初始化脚本执行完成");
