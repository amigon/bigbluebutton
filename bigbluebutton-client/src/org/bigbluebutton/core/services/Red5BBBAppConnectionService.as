package org.bigbluebutton.core.services
{
    import flash.events.AsyncErrorEvent;
    import flash.events.IEventDispatcher;
    import flash.events.IOErrorEvent;
    import flash.events.NetStatusEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.TimerEvent;
    import flash.net.NetConnection;
    import flash.net.Responder;
    import flash.utils.Timer;
    
    import org.bigbluebutton.common.LogUtil;
    import org.bigbluebutton.core.controllers.events.ConnectedToRed5Event;
    import org.bigbluebutton.core.controllers.events.ConnectionEvent;
    import org.bigbluebutton.core.controllers.events.ConnectionFailedEvent;
    import org.bigbluebutton.core.controllers.events.UsersConnectionEvent;
    import org.bigbluebutton.core.model.ConfigModel;
    import org.bigbluebutton.core.model.MeetingModel;
    import org.bigbluebutton.core.model.UsersModel;
    import org.bigbluebutton.core.vo.ConnectParameters;

    public class Red5BBBAppConnectionService
    {
        public var dispatcher:IEventDispatcher;
        public var meetingModel:MeetingModel;   
        public var configModel:ConfigModel; 
        public var usersModel:UsersModel;
        
        private var _netConnection:NetConnection;	        
        private var _connectParams:ConnectParameters;
        private var _connUri:String;
        
        public function get connectionUri():String {
            return _connUri;
        }
        
        public function get connection():NetConnection {
            return _netConnection;
        }
        

        public function connect():void
        {	
            _connectParams = getConnectParams();
            connectToRed5();	
        }
        
        private function getConnectParams():ConnectParameters {
            var params:ConnectParameters = new ConnectParameters();
            params.conference = usersModel.loggedInUser.conference;
            params.uri = configModel.applicationURI;
            params.externUserID = usersModel.loggedInUser.externUserID;
            params.internalUserID = usersModel.loggedInUser.internalUserID;
            params.room = usersModel.loggedInUser.room;
            params.username = usersModel.loggedInUser.username;
            params.role = usersModel.loggedInUser.role;
            params.record = usersModel.loggedInUser.record;
            params.voicebridge = usersModel.loggedInUser.voicebridge;
            
            return params;
        }
        
        private var rtmpTimer:Timer = null;
        private const ConnectionTimeout:int = 5000;
        
        private function connectToRed5(rtmpt:Boolean=false):void
        {
            var uri:String = _connectParams.uri + "/" + _connectParams.room;
            
            _netConnection = new NetConnection();
            _netConnection.client = this;
            _netConnection.addEventListener(NetStatusEvent.NET_STATUS, connectionHandler);
            _netConnection.addEventListener(AsyncErrorEvent.ASYNC_ERROR, netASyncError);
            _netConnection.addEventListener(SecurityErrorEvent.SECURITY_ERROR, netSecurityError);
            _netConnection.addEventListener(IOErrorEvent.IO_ERROR, netIOError);
            _connUri = (rtmpt ? "rtmpt:" : "rtmp:") + "//" + uri
            LogUtil.debug("Connect to " + uri);
            _netConnection.connect(_connUri, _connectParams.username, _connectParams.role, _connectParams.conference, 
                _connectParams.room, _connectParams.voicebridge, _connectParams.record, _connectParams.externUserID, _connectParams.internalUserID);
            if (!rtmpt) {
                rtmpTimer = new Timer(ConnectionTimeout, 1);
                rtmpTimer.addEventListener(TimerEvent.TIMER_COMPLETE, rtmpTimeoutHandler);
                rtmpTimer.start();
            }
        }
        
        private function rtmpTimeoutHandler(e:TimerEvent):void
        {
            _netConnection.close();
            _netConnection = null;
            
            connectToRed5(true);
        }
        
        private function connectionHandler(e:NetStatusEvent):void
        {
            if (rtmpTimer) {
                rtmpTimer.stop();
                rtmpTimer = null;
            }
            
            handleResult(e);
        }
        
        public function disconnect(logoutOnUserCommand:Boolean):void
        {
            _netConnection.close();
        }
                
        private function getMyUserID():void {
            LogUtil.debug("Getting user id");
            _netConnection.call(
                "getMyUserId",// Remote function name
                new Responder(
                    // result - On successful result
                    function(result:Object):void { 
                        var useridString:String = result as String;
                        meetingModel.myUserID = useridString;
                        var e:UsersConnectionEvent = new UsersConnectionEvent(UsersConnectionEvent.CONNECTION_SUCCESS);
                        e.connection = _netConnection;
                        e.userid = useridString;
                        dispatcher.dispatchEvent(e);
                    },	
                    // status - On error occurred
                    function(status:Object):void { 
                        LogUtil.error("getMyUserID Error occurred:"); 
                    }
                )//new Responder
            ); //_netConnection.call            
        }
        
        public function handleResult(event:NetStatusEvent):void {
            var info:Object = event.info;
            var statusCode:String = info.code;
            
            switch (statusCode) 
            {
                case "NetConnection.Connect.Success":
             //       _dispatcher.dispatchEvent(new ConnectedToRed5Event()); 
                    LogUtil.debug("Connected");
                    getMyUserID();
                    break;
                
                case "NetConnection.Connect.Failed":					
                    dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.CONNECTION_FAILED));								
                    break;
                
                case "NetConnection.Connect.Closed":				
                    dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.CONNECTION_CLOSED));								
                    break;
                
                case "NetConnection.Connect.InvalidApp":			
                    dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.INVALID_APP));				
                    break;
                
                case "NetConnection.Connect.AppShutDown":
                    dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.APP_SHUTDOWN));	
                    break;
                
                case "NetConnection.Connect.Rejected":
                    dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.CONNECTION_REJECTED));		
                    break;
                
                case "NetConnection.Connect.NetworkChange":
                    dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.CONNECTION_NETWORK_CHANGE_EVENT));
                    break;
                
                default:                
                    dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.UNKNOWN_REASON));
                    break;
            }
        }
        
        protected function netSecurityError(event:SecurityErrorEvent):void 
        {
            dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.UNKNOWN_REASON));
        }
        
        protected function netIOError(event:IOErrorEvent):void 
        {
            LogUtil.debug("Input/output error - " + event.text);
            dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.UNKNOWN_REASON));
        }
        
        protected function netASyncError(event:AsyncErrorEvent):void 
        {
            LogUtil.debug("Asynchronous code error - " + event.error);
            dispatcher.dispatchEvent(new ConnectionEvent(ConnectionEvent.UNKNOWN_REASON));
        }	
        
        /**
         *  Callback from server
         */
        public function setUserId(id:Number, role:String):String
        {
            LogUtil.debug( "ViewersNetDelegate::setConnectionId: id=[" + id + "," + role + "]");
            if (isNaN(id)) return "FAILED";
            
            // We should be receiving authToken and room from the server here.
            //_userid = id;								
            return "OK";
        }
               
        public function onBWCheck(... rest):Number { 
            return 0; 
        } 
        
        public function onBWDone(... rest):void { 
            var p_bw:Number; 
            if (rest.length > 0) p_bw = rest[0]; 
            // your application should do something here 
            // when the bandwidth check is complete 
            trace("bandwidth = " + p_bw + " Kbps."); 
        }
    }
}